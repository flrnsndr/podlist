import Foundation
import SwiftData
import os

public enum FeedRefreshError: Error, Hashable, Sendable {
    /// Not an http(s)/feed URL.
    case invalidURL
    /// The server answered 304 without being asked conditionally.
    case unexpectedNotModified
}

/// Result of refreshing every subscribed podcast.
public struct RefreshSummary: Hashable, Sendable {
    /// Feeds loaded or not modified.
    public var refreshed = 0
    public var failures = 0
    /// Feeds not refreshed: the budget ran out or the run was cancelled.
    public var skipped = 0
    /// `uuid`s of the new episodes, per podcast in feed order.
    public var newEpisodes: [UUID] = []

    /// Every feed was tried; a run cut short is not complete (A63).
    public var isComplete: Bool { skipped == 0 }
}

/// How one task of "refresh all" ended.
private enum RefreshOutcome: Sendable {
    case refreshed([UUID])
    case failed
    case cancelled
    /// The budget ran out.
    case deadline
    /// The budget's timer stopped because every feed was done.
    case timerStopped
}

/// Loads feeds and writes podcasts and episodes in background contexts (concept §6.3, §6.5).
/// Only UUIDs and value types leave the actor.
///
/// Every write reads its podcast and episodes in a fresh context right before it changes
/// them, after any network load, and saves without waiting in between. The main context
/// changes the same models all the time (listening position, played status, downloads,
/// settings); saving a model this actor read earlier writes those older values back.
public actor FeedRefresher: ModelActor {
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let modelExecutor: any ModelExecutor
    private let loader: FeedLoader
    /// "Refresh all" holds back the saves of feeds without new episodes (validators,
    /// `lastRefreshedAt`, changed show notes) and writes them together at the end: every save
    /// wakes the main context and with it every `@Query` on screen, so one save per feed made
    /// the app stutter during a refresh. A feed with new episodes saves at once, so they can be
    /// notified before the run is over (A44). The held-back feeds are kept as values, not as
    /// changed models, and written again in a fresh context at the end (see the type comment).
    private var deferred: [UUID: DeferredRefresh] = [:]

    /// A feed of "refresh all" whose save waits for the end of the run.
    private struct DeferredRefresh {
        let now: Date
        /// nil: not modified, or the refresh failed (only `lastRefreshedAt` changes).
        let loaded: LoadedFeed?
    }

    /// A feed as loaded and parsed, with what the server said about it.
    private struct LoadedFeed {
        let feed: ParsedFeed
        let etag: String?
        let lastModified: String?
        let movedTo: URL?
    }

    /// Parallel feed requests for "refresh all" and the OPML import.
    public static let maxConcurrentLoads = 6

    public init(modelContainer: ModelContainer, loader: FeedLoader) {
        self.modelContainer = modelContainer
        self.modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(modelContainer))
        self.loader = loader
    }

    /// Loads and parses a feed without storing anything (podcast preview before subscribing).
    public func preview(_ url: URL) async throws -> ParsedFeed {
        guard let url = try await feedURL(url) else { throw FeedRefreshError.invalidURL }
        guard let loaded = try await load(url) else { throw FeedRefreshError.unexpectedNotModified }
        return loaded.feed
    }

    /// Subscribes to a feed and returns the podcast's `uuid`. A podcast that was
    /// unsubscribed comes back with its episodes and listening state (concept §4.9).
    /// `arrival`: `.subscribe` puts the newest episode into the inbox, `.opmlImport` none (A49).
    public func subscribe(_ url: URL, now: Date, arrival: InboxArrival = .subscribe) async throws -> UUID {
        guard let url = try await feedURL(url) else { throw FeedRefreshError.invalidURL }
        if let existing = try podcast(feedURL: url, in: ModelContext(modelContainer)) {
            return try await resubscribe(existing.uuid, now: now, arrival: arrival)
        }
        guard let loaded = try await load(url) else { throw FeedRefreshError.unexpectedNotModified }
        let feed = loaded.feed
        let feedURL = feed.newFeedURL.flatMap(FeedLoader.normalizedFeedURL) ?? loaded.movedTo ?? url
        let context = ModelContext(modelContainer)
        // A parallel call (e.g. the OPML import) may have inserted it while we were loading.
        if let existing = try podcast(feedURL: url, in: context) ?? podcast(feedURL: feedURL, in: context) {
            return try await resubscribe(existing.uuid, now: now, arrival: arrival)
        }

        let podcast = Podcast(feedURL: feedURL, title: feed.title, subscribedAt: now)
        podcast.notificationsEnabled = true  // N35
        context.insert(podcast)
        apply(feed, to: podcast)
        if feedURL == url {
            podcast.etag = loaded.etag
            podcast.lastModified = loaded.lastModified
        }
        podcast.lastRefreshedAt = now
        let inserted = merge(feed.episodes, into: podcast, now: now, in: context)
        takeIntoInbox(inserted, arrival: arrival, now: now)
        try context.save()
        Logger.feeds.info("Subscribed to \(feedURL.absoluteString, privacy: .public): \(feed.episodes.count) episodes")
        return podcast.uuid
    }

    /// Refreshes one subscribed podcast and returns the `uuid`s of its new episodes.
    @discardableResult
    public func refresh(_ podcastID: UUID, now: Date) async throws -> [UUID] {
        try await refresh(podcastID, now: now, arrival: .refresh, deferringSaves: false)
    }

    /// `arrival`: a plain refresh, or the first refresh after subscribing again. With
    /// `deferringSaves` a feed without new episodes is not saved yet (see `deferred`).
    @discardableResult
    private func refresh(_ podcastID: UUID, now: Date, arrival: InboxArrival, deferringSaves: Bool) async throws -> [UUID] {
        guard let podcast = try podcast(uuid: podcastID, in: ModelContext(modelContainer)), podcast.isSubscribed else { return [] }
        let loaded = try await load(podcast.feedURL, etag: podcast.etag, lastModified: podcast.lastModified)
        // The load took a while: read the podcast and its episodes again, as stored now.
        let context = ModelContext(modelContainer)
        guard let current = try self.podcast(uuid: podcastID, in: context), current.isSubscribed else { return [] }
        let inserted = try write(loaded, to: current, now: now, arrival: arrival, in: context)
        if deferringSaves && inserted.isEmpty {
            // Dropped unsaved; written again at the end of the run.
            deferred[podcastID] = DeferredRefresh(now: now, loaded: loaded)
            return []
        }
        try context.save()
        return inserted.map(\.uuid)
    }

    /// Writes a refresh into `podcast` (read in `context`, not saved here) and returns the new
    /// episodes. `loaded`: nil when the feed was not modified.
    private func write(
        _ loaded: LoadedFeed?, to podcast: Podcast, now: Date, arrival: InboxArrival, in context: ModelContext
    ) throws -> [Episode] {
        podcast.lastRefreshedAt = now
        guard let loaded else { return [] }
        let feed = loaded.feed
        let url = podcast.feedURL
        apply(feed, to: podcast)
        if let moved = feed.newFeedURL.flatMap(FeedLoader.normalizedFeedURL) ?? loaded.movedTo, moved != url {
            Logger.feeds.notice("Feed moved: \(url.absoluteString, privacy: .public) → \(moved.absoluteString, privacy: .public)")
            podcast.feedURL = moved
            podcast.etag = nil
            podcast.lastModified = nil
        } else {
            podcast.etag = loaded.etag
            podcast.lastModified = loaded.lastModified
        }
        let podcastID = podcast.uuid
        let inserted = merge(
            feed.episodes, into: podcast, now: now, in: context, storedChapterSources: try storedChapterSources(of: podcastID))
        if arrival == .refresh {
            takeIntoInbox(inserted, arrival: arrival, now: now)
        } else {
            // Subscribing again: the kept episodes are candidates too (§4.9). Whether they are in
            // a playlist is read fresh: the main context may have removed entries this context still holds.
            let new = Set(inserted.map(\.uuid))
            let kept = (podcast.episodes ?? []).filter { !new.contains($0.uuid) }
            takeIntoInbox(inserted + kept, arrival: arrival, now: now, inPlaylists: try episodesInPlaylists(of: podcastID))
        }
        // After the inbox, so that episodes sorted completely by auto-add arrive done (N75).
        autoAdd(inserted, of: podcast, now: now, in: context)
        return inserted
    }

    /// Refreshes every subscribed podcast in `RefreshSchedule` order, so a run cut short
    /// (background time ran out, A44) goes on there next time. After `budget` no feed starts
    /// and running loads stop; cancelling starts no more feeds. `onNewEpisodes` gets each
    /// podcast's new episodes as soon as its feed is done.
    public func refreshAll(
        now: Date, budget: Duration? = nil, onNewEpisodes: @escaping @Sendable ([UUID]) async -> Void = { _ in }
    ) async throws -> RefreshSummary {
        let descriptor = FetchDescriptor<Podcast>(predicate: #Predicate { $0.isSubscribed })
        let ids = RefreshSchedule.order(try ModelContext(modelContainer).fetch(descriptor).map { podcast in
            RefreshCandidate(
                podcast: PodcastID(podcast.uuid), lastRefreshedAt: podcast.lastRefreshedAt,
                isWatched: podcast.notificationsEnabled || !(podcast.assignments ?? []).isEmpty)
        }).map(\.uuid)
        return await withTaskGroup(of: RefreshOutcome.self) { group in
            var pending = ids[...]
            var running = 0
            var isOverBudget = false
            var summary = RefreshSummary()
            func addNext() {
                guard !isOverBudget, !Task.isCancelled, let id = pending.popFirst() else { return }
                running += 1
                group.addTask {
                    do {
                        return .refreshed(try await self.refresh(id, now: now, arrival: .refresh, deferringSaves: true))
                    } catch {
                        // Attempted all the same: a dead or hanging feed must not stay first (A44).
                        await self.markAttempted(id, now: now)
                        if Task.isCancelled { return .cancelled }
                        Logger.feeds.error("Refresh failed for \(id, privacy: .public): \(String(describing: error), privacy: .public)")
                        return .failed
                    }
                }
            }
            if let budget {
                group.addTask {
                    do {
                        try await Task.sleep(for: budget)
                        return .deadline
                    } catch {
                        return .timerStopped
                    }
                }
            }
            for _ in 0..<Self.maxConcurrentLoads { addNext() }
            if running == 0 { group.cancelAll() }
            while let outcome = await group.next() {
                switch outcome {
                case .refreshed(let new):
                    running -= 1
                    summary.refreshed += 1
                    summary.newEpisodes += new
                    addNext()
                    if !new.isEmpty { await onNewEpisodes(new) }
                case .failed:
                    running -= 1
                    summary.failures += 1
                    addNext()
                case .cancelled:
                    running -= 1
                case .deadline:
                    isOverBudget = true
                    group.cancelAll()
                case .timerStopped:
                    break
                }
                // Every feed is done: stop the timer.
                if running == 0 { group.cancelAll() }
            }
            summary.skipped = ids.count - summary.refreshed - summary.failures
            saveDeferredChanges()
            return summary
        }
    }

    private func markAttempted(_ podcastID: UUID, now: Date) {
        deferred[podcastID] = DeferredRefresh(now: now, loaded: nil)
    }

    /// Writes the held-back feeds of "refresh all" in one save, read fresh.
    private func saveDeferredChanges() {
        guard !deferred.isEmpty else { return }
        let context = ModelContext(modelContainer)
        do {
            for (podcastID, refresh) in deferred {
                guard let podcast = try podcast(uuid: podcastID, in: context), podcast.isSubscribed else { continue }
                _ = try write(refresh.loaded, to: podcast, now: refresh.now, arrival: .refresh, in: context)
            }
            try context.save()
        } catch {
            Logger.feeds.error("Saving the refresh failed: \(String(describing: error), privacy: .public)")
        }
        deferred = [:]
    }

    // MARK: Loading

    /// The URL a podcast is stored with: normalized, and for an ARD Sounds episode link the
    /// page of its show (concept §4.13).
    private func feedURL(_ url: URL) async throws -> URL? {
        guard let url = FeedLoader.normalizedFeedURL(url) else { return nil }
        guard let reference = ARDSounds.reference(from: url), case .episode = reference else { return url }
        return ARDSounds.showURL(try await loader.ard.showURN(for: reference))
    }

    /// Loads and parses a feed; `nil` if it was not modified. An ARD-backed podcast (its feed
    /// URL is an ARD Sounds show page) is asked for its state first, which stands in for the
    /// conditional request; `lastModified` holds that state.
    private func load(_ url: URL, etag: String? = nil, lastModified: String? = nil) async throws -> LoadedFeed? {
        if case .show(let urn) = ARDSounds.reference(from: url) {
            if let lastModified, try await loader.ard.state(of: urn) == lastModified { return nil }
            let show = try await loader.ard.show(urn)
            return LoadedFeed(feed: show.feed, etag: nil, lastModified: show.validator, movedTo: nil)
        }
        switch try await loader.load(url, etag: etag, lastModified: lastModified) {
        case .notModified:
            return nil
        case .loaded(let data, let etag, let lastModified, let movedTo):
            return LoadedFeed(feed: try FeedParser.parse(data), etag: etag, lastModified: lastModified, movedTo: movedTo)
        }
    }

    // MARK: Writing

    private func resubscribe(_ podcastID: UUID, now: Date, arrival: InboxArrival) async throws -> UUID {
        let context = ModelContext(modelContainer)
        if let podcast = try podcast(uuid: podcastID, in: context), !podcast.isSubscribed {
            podcast.isSubscribed = true
            podcast.subscribedAt = now
            podcast.notificationsEnabled = true  // N35
            // Unsubscribing deleted unreferenced episodes; load the full feed again.
            podcast.etag = nil
            podcast.lastModified = nil
            try context.save()
            try await refresh(podcastID, now: now, arrival: arrival, deferringSaves: false)
        }
        return podcastID
    }

    private func apply(_ feed: ParsedFeed, to podcast: Podcast) {
        podcast.setIfChanged(\.title, feed.title)
        podcast.setIfChanged(\.author, feed.author)
        podcast.setIfChanged(\.summary, feed.summary)
        podcast.setIfChanged(\.artworkURL, feed.artworkURL)
        podcast.setIfChanged(\.link, feed.link)
        podcast.setIfChanged(\.categories, feed.categories)
    }

    /// Puts the entering episodes into the inbox (concept §4.10, A49, N48); `episodes` in feed
    /// order. `inPlaylists`: the `uuid`s of episodes in a playlist as stored right now.
    private func takeIntoInbox(_ episodes: [Episode], arrival: InboxArrival, now: Date, inPlaylists: Set<UUID>? = nil) {
        let candidates = episodes.map { episode in
            var candidate = episode.inboxCandidate
            if let inPlaylists { candidate.isInPlaylist = inPlaylists.contains(episode.uuid) }
            return candidate
        }
        let entering = Set(InboxRules.entering(candidates, arrival: arrival, now: now))
        for (episode, candidate) in zip(episodes, candidates) where entering.contains(candidate.id) {
            episode.inboxAddedAt = now
            episode.inboxState = InboxRules.initialState(of: candidate)
        }
    }

    /// New episodes go into the playlists the podcast is assigned to (concept §4.1).
    private func autoAdd(_ episodes: [Episode], of podcast: Podcast, now: Date, in context: ModelContext) {
        guard !episodes.isEmpty else { return }
        let infos = episodes.map(\.info)
        for assignment in podcast.assignments ?? [] {
            guard let playlist = assignment.playlist else { continue }
            let insertions = PlaylistAutomation.insertions(
                forNewEpisodes: infos,
                assignments: [PlaylistAssignmentInfo(playlistID: playlist.playlistID, rule: assignment.autoAdd)],
                existingEntries: [playlist.playlistID: (playlist.entries ?? []).compactMap(\.info)], now: now)
            PlaylistService.insert(insertions, into: playlist, episodes: episodes, context: context)
        }
        episodes.forEach { $0.inboxAutoAdded() }
    }

    /// Inserts new episodes and updates known ones; returns the new episodes.
    /// `storedChapterSources`: the chapter source of each known episode as stored right now.
    private func merge(
        _ items: [ParsedEpisode], into podcast: Podcast, now: Date, in context: ModelContext,
        storedChapterSources: [UUID: ChapterSource] = [:]
    ) -> [Episode] {
        let episodes = podcast.episodes ?? []
        let byID = Dictionary(episodes.map { (EpisodeID($0.uuid), $0) }, uniquingKeysWith: { first, _ in first })
        let keys = episodes.map {
            EpisodeKey(id: EpisodeID($0.uuid), guid: $0.guid, audioURL: $0.audioURL, title: $0.title, publishedAt: $0.publishedAt)
        }
        var inserted: [Episode] = []
        for action in FeedMerge.actions(existing: keys, parsed: items) {
            switch action {
            case .update(let id, let item):
                if let episode = byID[id] { apply(item, to: episode, storedChapterSource: storedChapterSources[episode.uuid]) }
            case .insert(let item):
                let episode = Episode(
                    guid: FeedMerge.storedGUID(for: item), title: item.title,
                    publishedAt: item.publishedAt ?? now, audioURL: item.audioURL)
                context.insert(episode)
                episode.podcast = podcast
                apply(item, to: episode, storedChapterSource: nil)
                inserted.append(episode)
            }
        }
        return inserted
    }

    private func apply(_ item: ParsedEpisode, to episode: Episode, storedChapterSource: ChapterSource?) {
        episode.setIfChanged(\.guid, FeedMerge.storedGUID(for: item))
        episode.setIfChanged(\.title, item.title)
        episode.setIfChanged(\.showNotes, item.showNotes)
        episode.setIfChanged(\.subtitle, item.subtitle)
        if let publishedAt = item.publishedAt { episode.setIfChanged(\.publishedAt, publishedAt) }
        // The real duration measured by the player wins over the feed's value.
        if episode.duration == nil { episode.duration = item.duration }
        episode.setIfChanged(\.audioURL, item.audioURL)
        if let fileSize = item.fileSize { episode.setIfChanged(\.fileSize, fileSize) }
        episode.setIfChanged(\.imageURL, item.imageURL)
        episode.setIfChanged(\.episodeNumber, item.episodeNumber)
        episode.setIfChanged(\.seasonNumber, item.seasonNumber)
        episode.setIfChanged(\.chaptersURL, item.chaptersURL)
        // Podlove chapters from the feed; only JSON chapters are better (ADR 0005). The
        // decision uses the stored source: the `ChapterService` writes chapters in the main
        // context, so this context's copy of the episode can be stale.
        if ChapterSelection.shouldReplace(storedChapterSource, with: .podlove) {
            let chapters = ChapterSelection.normalized(item.chapters, duration: episode.duration)
            if !chapters.isEmpty, storedChapterSource != .podlove || episode.chapters != chapters {
                episode.chapters = chapters
                episode.chaptersSource = .podlove
            }
        }
    }

    // MARK: Fetching

    /// The stored chapter sources of a podcast's episodes, read in a fresh context so that
    /// writes of the main context are seen.
    private func storedChapterSources(of podcastID: UUID) throws -> [UUID: ChapterSource] {
        let context = ModelContext(modelContainer)
        let episodes = try context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.podcast?.uuid == podcastID }))
        return Dictionary(
            episodes.compactMap { episode in episode.chaptersSource.map { (episode.uuid, $0) } },
            uniquingKeysWith: { first, _ in first })
    }

    /// The `uuid`s of a podcast's episodes that are in a playlist, read in a fresh context.
    private func episodesInPlaylists(of podcastID: UUID) throws -> Set<UUID> {
        let context = ModelContext(modelContainer)
        let episodes = try context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { $0.podcast?.uuid == podcastID }))
        return Set(episodes.filter { !($0.playlistEntries ?? []).isEmpty }.map(\.uuid))
    }

    private func podcast(uuid: UUID, in context: ModelContext) throws -> Podcast? {
        var descriptor = FetchDescriptor<Podcast>(predicate: #Predicate { $0.uuid == uuid })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func podcast(feedURL: URL, in context: ModelContext) throws -> Podcast? {
        try context.fetch(FetchDescriptor<Podcast>()).first { $0.feedURL == feedURL }
    }
}

extension PersistentModel {
    /// Writes only real changes, so a refresh does not dirty thousands of unchanged episodes.
    func setIfChanged<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<Self, Value>, _ value: Value) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}
