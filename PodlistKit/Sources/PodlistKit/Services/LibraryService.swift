import Foundation
import Observation
import SwiftData
import os

/// Result of an OPML import.
public struct OPMLImportResult: Hashable, Sendable {
    public var subscribed: Int
    public var alreadySubscribed: Int
    /// In the file's order.
    public var failed: [OPMLImportFailure]
}

/// A podcast of the OPML file that could not be subscribed, and why.
public struct OPMLImportFailure: Hashable, Sendable {
    public var outline: OPMLOutline
    public var reason: FeedFailureReason
}

/// Subscriptions, refreshing and the played status / listening position of episodes
/// (concept §4.3, §4.9). Feed work runs in the `FeedRefresher`'s background context.
@MainActor @Observable
public final class LibraryService {
    public private(set) var isRefreshing = false
    /// Progress of a running OPML import: done / total.
    public private(set) var importProgress: (done: Int, total: Int)?
    /// The end of the last refresh that tried every feed, in this app run (A63).
    private var lastCompleteRefresh: Date?

    private let context: ModelContext
    private let refresher: FeedRefresher
    private let downloads: DownloadService?
    private let notifications: NotificationScheduler?
    private let chapterImages: ChapterImageStore
    private let now: @Sendable () -> Date

    /// `downloads` loads new playlist episodes and deletes played downloads (concept §4.7);
    /// `notifications` announces new episodes (N35).
    public init(
        container: ModelContainer, loader: FeedLoader = FeedLoader(), downloads: DownloadService? = nil,
        notifications: NotificationScheduler? = nil, chapterImages: ChapterImageStore = .shared,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.context = container.mainContext
        self.refresher = FeedRefresher(modelContainer: container, loader: loader)
        self.downloads = downloads
        self.notifications = notifications
        self.chapterImages = chapterImages
        self.now = now
    }

    // MARK: Subscriptions

    public func preview(_ url: URL) async throws -> ParsedFeed {
        try await refresher.preview(url)
    }

    /// Notifications are on for every subscription (N35); the first one asks for permission (A47).
    @discardableResult
    public func subscribe(to url: URL) async throws -> Podcast? {
        let id = try await refresher.subscribe(url, now: now())
        await notifications?.requestAuthorizationIfNeeded()
        return try podcast(uuid: id)
    }

    public func isSubscribed(feedURL url: URL) throws -> Bool {
        guard let url = FeedLoader.normalizedFeedURL(url) else { return false }
        return try subscribedFeedURLs().contains(url)
    }

    /// Subscribes to every podcast of an OPML file, a few feeds at a time.
    public func importOPML(_ data: Data) async throws -> OPMLImportResult {
        let outlines = try OPMLParser.parse(data)
        let known = try subscribedFeedURLs()
        let new = outlines.filter { FeedLoader.normalizedFeedURL($0.feedURL).map(known.contains) != true }
        var result = OPMLImportResult(subscribed: 0, alreadySubscribed: outlines.count - new.count, failed: [])
        importProgress = (0, new.count)
        defer { importProgress = nil }

        let refresher = refresher
        let date = now()
        await withTaskGroup(of: (OPMLOutline, FeedFailureReason?).self) { group in
            var pending = new[...]
            func addNext() {
                guard let outline = pending.popFirst() else { return }
                group.addTask {
                    do {
                        _ = try await refresher.subscribe(outline.feedURL, now: date, arrival: .opmlImport)
                        return (outline, nil)
                    } catch {
                        Logger.feeds.error("OPML import failed for \(outline.feedURL.absoluteString, privacy: .public): \(String(describing: error), privacy: .public)")
                        return (outline, FeedFailureReason(error))
                    }
                }
            }
            for _ in 0..<FeedRefresher.maxConcurrentLoads { addNext() }
            for await (outline, reason) in group {
                if let reason {
                    result.failed.append(OPMLImportFailure(outline: outline, reason: reason))
                } else {
                    result.subscribed += 1
                }
                importProgress = (result.subscribed + result.failed.count, new.count)
                addNext()
            }
        }
        await notifications?.requestAuthorizationIfNeeded()
        // Keep the file's order for the failure list.
        result.failed.sort { a, b in
            (new.firstIndex(of: a.outline) ?? 0) < (new.firstIndex(of: b.outline) ?? 0)
        }
        return result
    }

    /// Unsubscribes (concept §4.9): the podcast stays as `isSubscribed = false`, its
    /// assignments go, and only episodes nothing needs any more are deleted.
    ///
    /// ASSUMPTION (A10): episodes with a listening state (played or started) are kept too,
    /// so subscribing again brings back the listening state. Downloads stay with their
    /// files; deleted episodes take their cached chapter images along (A42). The podcast
    /// remembers its playlists for the listening history (N85, A74).
    public func unsubscribe(_ podcast: Podcast) throws {
        podcast.isSubscribed = false
        podcast.playlistUUIDsBeforeUnsubscribing = (podcast.assignments ?? []).compactMap { $0.playlist?.uuid }
        (podcast.assignments ?? []).forEach(context.delete)
        let inHistory = try episodeIDsInHistory()
        var deleted: Set<UUID> = []
        for episode in podcast.episodes ?? [] {
            let isNeeded = !(episode.playlistEntries ?? []).isEmpty
                || !(episode.queueItems ?? []).isEmpty
                || inHistory.contains(EpisodeID(episode.uuid))
                || episode.downloadState != .none
                || episode.isPlayed
                || episode.playbackPosition > 0
            if !isNeeded {
                context.delete(episode)
                deleted.insert(episode.uuid)
            }
        }
        try context.save()
        chapterImages.removeImages(of: deleted)
        Logger.library.info("Unsubscribed \(podcast.title, privacy: .public), deleted \(deleted.count) episodes")
    }

    // MARK: Refreshing

    /// Refreshes every subscribed podcast and notifies each podcast's new episodes as soon as
    /// its feed is done (A44). `budget`: the background refresh stops loading after it.
    public func refreshAll(budget: Duration? = nil) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let kind = budget == nil ? "Refresh" : "Background refresh"
        let clock = ContinuousClock()
        let start = clock.now
        let notifications = notifications
        do {
            let summary = try await refresher.refreshAll(now: now(), budget: budget) { @MainActor ids in
                await notifications?.notifyNewEpisodes(ids)
            }
            if summary.isComplete { lastCompleteRefresh = now() }
            let seconds = (clock.now - start).formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow))
            Logger.feeds.notice("\(kind, privacy: .public) took \(seconds, privacy: .public): \(summary.refreshed) refreshed, \(summary.failures) failed, \(summary.skipped) skipped, \(summary.newEpisodes.count) new episodes")
        } catch {
            Logger.feeds.error("\(kind, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
        downloads?.evaluate()
    }

    /// Returning to the app: refreshes unless a complete refresh ran in the last minutes (A63).
    public func refreshAllIfDue() async {
        guard RefreshSchedule.isDue(lastCompleteRefresh: lastCompleteRefresh, now: now()) else { return }
        await refreshAll()
    }

    public func refresh(_ podcast: Podcast) async throws {
        let newEpisodes = try await refresher.refresh(podcast.uuid, now: now())
        downloads?.evaluate()
        await notifications?.notifyNewEpisodes(newEpisodes)
    }


    // MARK: Notifications

    /// New-episode notifications of one podcast (N35).
    public func setNotificationsEnabled(_ isOn: Bool, for podcast: Podcast) throws {
        podcast.notificationsEnabled = isOn
        try context.save()
        if isOn { Task { await notifications?.requestAuthorizationIfNeeded() } }
    }

    /// N36: turns notifications on for every subscribed podcast; the app does this once.
    public func enableNotificationsForSubscribedPodcasts() throws {
        let podcasts = try context.fetch(FetchDescriptor<Podcast>(predicate: #Predicate { $0.isSubscribed }))
        for podcast in podcasts { podcast.notificationsEnabled = true }
        try context.save()
        Logger.library.info("Notifications turned on for \(podcasts.count) podcasts")
    }

    // MARK: Played status and position

    /// "Als gespielt markieren": the position goes back to 0, so it starts over (A8).
    /// Unless it is in the player, the episode leaves "remove" playlists and loses its
    /// download (N32).
    public func markPlayed(_ episode: Episode) throws {
        episode.playedAt = episode.playedAt ?? now()
        episode.playbackPosition = 0
        episode.inboxHandled()
        try applyPlayedRules(to: episode)
    }

    /// Applies the played policy (concept §4.3) and deletes the download (A37) once a
    /// played episode has left the player.
    public func applyPlayedPolicy(to episode: Episode) throws {
        try applyPlayedRules(to: episode)
    }

    public func markUnplayed(_ episode: Episode) throws {
        episode.playedAt = nil
        try context.save()
        downloads?.evaluate()
    }

    private func applyPlayedRules(to episode: Episode) throws {
        try PlaylistEntryRemoval.applyPlayedPolicy(to: episode, context: context)
        downloads?.deletePlayedDownloadIfNeeded(episode)
        try context.save()
    }

    /// Where playback of the episode would start, without changing anything: the stored
    /// position, or the start if the episode is played (N23) or at the very end; after the
    /// podcast's intro if it would start inside it (A28).
    public func startPosition(of episode: Episode) -> TimeInterval {
        PlaybackRules.startPosition(
            stored: episode.playbackPosition, isPlayed: episode.isPlayed, duration: episode.duration,
            skipIntro: TimeInterval(episode.podcast?.skipIntroSeconds ?? 0))
    }

    /// The user starts an episode in the player. A played episode counts as unplayed again
    /// (N9), also in a keep playlist. Returns the position to start at.
    public func playbackWillStart(_ episode: Episode) throws -> TimeInterval {
        let stored = episode.playbackPosition
        episode.playbackPosition = startPosition(of: episode)
        if stored > 0, episode.playbackPosition < stored {
            Logger.playback.info("\(episode.uuid, privacy: .public) starts at \(episode.playbackPosition, format: .fixed(precision: 0)) s, not at its position \(stored, format: .fixed(precision: 0)) s (played: \(episode.isPlayed), duration: \(episode.duration ?? 0, format: .fixed(precision: 0)) s)")
        }
        if episode.isPlayed { episode.playedAt = nil }
        try context.save()
        return episode.playbackPosition
    }

    /// Stores the listening position; "almost at the end" marks the episode played (§4.3)
    /// and keeps the position.
    public func saveProgress(_ episode: Episode, position: TimeInterval) throws {
        episode.playbackPosition = max(0, position)
        if !episode.isPlayed, PlayedRules.isNearEnd(position: position, duration: episode.duration) {
            Logger.playback.info("\(episode.uuid, privacy: .public) played: \(position, format: .fixed(precision: 0)) s of \(episode.duration ?? 0, format: .fixed(precision: 0)) s")
            episode.playedAt = now()
        }
        try context.save()
    }

    /// The episode played to its end: played, and the position goes back to 0 (A8).
    public func episodeDidEnd(_ episode: Episode) throws {
        episode.playedAt = episode.playedAt ?? now()
        episode.playbackPosition = 0
        try context.save()
    }

    /// The player measured the real duration (concept §8: feeds often state it wrong).
    public func updateDuration(_ episode: Episode, to duration: TimeInterval) throws {
        guard duration.isFinite, duration > 0, abs((episode.duration ?? 0) - duration) >= 1 else { return }
        episode.duration = duration
        try context.save()
    }

    // MARK: Undo of ⏭ (N101, A81)

    /// What ⏭ changes about an episode: its played status, its position and the playlist
    /// entries the played policy removes.
    struct ListeningState {
        struct Entry {
            let playlist: PlaylistID
            let position: Double
            let addedAt: Date
            let origin: EntryOrigin
        }

        let playedAt: Date?
        let position: TimeInterval
        let entries: [Entry]
    }

    func listeningState(of episode: Episode) -> ListeningState {
        ListeningState(
            playedAt: episode.playedAt, position: episode.playbackPosition,
            entries: (episode.playlistEntries ?? []).compactMap { entry in
                entry.playlist.map {
                    ListeningState.Entry(playlist: $0.playlistID, position: entry.position, addedAt: entry.addedAt, origin: entry.origin)
                }
            })
    }

    /// Sets the episode back as it was: played status, position and the entries it lost, at
    /// their former place (a playlist deleted meanwhile stays gone). Saves.
    func restore(_ state: ListeningState, of episode: Episode) throws {
        episode.playedAt = state.playedAt
        episode.playbackPosition = state.position
        let store = UpNextStore(context: context)
        let current = Set((episode.playlistEntries ?? []).compactMap { $0.playlist?.playlistID })
        for entry in state.entries where !current.contains(entry.playlist) {
            guard let playlist = try store.playlist(entry.playlist) else { continue }
            context.insert(PlaylistEntry(
                playlist: playlist, episode: episode, position: entry.position, addedAt: entry.addedAt, origin: entry.origin))
        }
        try context.save()
    }

    /// While ⏭ can be undone, the skipped episode keeps its download (A37 waits).
    func keepDownloadForUndo(_ episode: Episode) {
        downloads?.keepForUndo(episode)
    }

    /// The undo is gone: the played-download rule applies again.
    func releaseDownloadKeptForUndo(_ episode: Episode) {
        downloads?.releaseKeptForUndo(episode)
    }

    // MARK: Player settings per podcast

    /// The podcast's own speed (N25); nil = the global speed.
    public func setPlaybackSpeed(_ speed: Double?, for podcast: Podcast) throws {
        podcast.playbackSpeed = speed.map(PlaybackRules.clampedSpeed)
        try context.save()
    }

    /// Seconds skipped at the start of every episode (A28); 0 = off.
    public func setSkipIntro(_ seconds: Int, for podcast: Podcast) throws {
        podcast.skipIntroSeconds = max(0, seconds)
        try context.save()
    }

    /// Seconds before the end where an episode counts as finished (N28); 0 = off.
    public func setSkipOutro(_ seconds: Int, for podcast: Podcast) throws {
        podcast.skipOutroSeconds = max(0, seconds)
        try context.save()
    }

    // MARK: Fetching

    private func podcast(uuid: UUID) throws -> Podcast? {
        var descriptor = FetchDescriptor<Podcast>(predicate: #Predicate { $0.uuid == uuid })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func subscribedFeedURLs() throws -> Set<URL> {
        Set(try context.fetch(FetchDescriptor<Podcast>(predicate: #Predicate { $0.isSubscribed })).map(\.feedURL))
    }

    private func episodeIDsInHistory() throws -> Set<EpisodeID> {
        var ids: Set<EpisodeID> = []
        for snapshot in try context.fetch(FetchDescriptor<UpNextSnapshot>()) {
            guard let state = try? snapshot.value().state else { continue }
            if let playing = state.nowPlaying { ids.insert(playing) }
            ids.formUnion(state.items)
        }
        return ids
    }
}
