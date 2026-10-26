import Foundation
import SwiftData
import Testing
import os
@testable import PodlistKit

/// New-episode notifications end to end: subscribing, refreshing, the category with or
/// without "Zu Playlists hinzufügen", permission (N34–N36, A45, A47).
@MainActor
struct NotificationSchedulerTests {
    private let container: ModelContainer
    private let routes = StubURLProtocol.Routes()
    private let center: FakeNotificationCenter
    private let library: LibraryService
    private var context: ModelContext { container.mainContext }
    /// 2026-10-10 12:00 UTC
    private nonisolated static let now = Date(timeIntervalSince1970: 1_791_633_600)
    private let feedURL = URL(string: "https://example.com/feed.xml")!

    init() throws {
        try self.init(center: FakeNotificationCenter(authorization: .notDetermined))
    }

    private init(center: FakeNotificationCenter) throws {
        container = try PodlistStore.makeContainer(inMemory: true)
        self.center = center
        let scheduler = NotificationScheduler(context: container.mainContext, center: center, now: { Self.now })
        library = LibraryService(
            container: container, loader: FeedLoader(session: StubURLProtocol.session(routes: routes)),
            notifications: scheduler, now: { Self.now })
    }

    // MARK: Subscribing

    /// N35, A47: on for every subscription; the first one asks for permission, once.
    @Test func subscribingTurnsNotificationsOnAndAsksOnce() async throws {
        serve(feedURL, feed([("g1", "One", "09 Oct 2026")]))
        let podcast = try #require(try await library.subscribe(to: feedURL))
        let other = URL(string: "https://other.example.com/feed.xml")!
        serve(other, feed([("o1", "Other", "09 Oct 2026")]))
        try await library.subscribe(to: other)

        #expect(podcast.notificationsEnabled)
        #expect(center.authorizationRequests == 1)
        #expect(center.posted.isEmpty, "subscribing notifies nothing")
    }

    @Test func resubscribingTurnsNotificationsOnAgain() async throws {
        serve(feedURL, feed([("g1", "One", "09 Oct 2026")]))
        let podcast = try #require(try await library.subscribe(to: feedURL))
        try library.setNotificationsEnabled(false, for: podcast)
        try library.unsubscribe(podcast)
        try await library.subscribe(to: feedURL)
        #expect(try fresh(podcast).notificationsEnabled)
    }

    /// N36
    @Test func enablingForSubscribedPodcastsSkipsUnsubscribedOnes() async throws {
        serve(feedURL, feed([("g1", "One", "09 Oct 2026")]))
        let podcast = try #require(try await library.subscribe(to: feedURL))
        let other = URL(string: "https://other.example.com/feed.xml")!
        serve(other, feed([("o1", "Other", "09 Oct 2026")]))
        let unsubscribed = try #require(try await library.subscribe(to: other))
        try library.setNotificationsEnabled(false, for: podcast)
        try library.setNotificationsEnabled(false, for: unsubscribed)
        try library.unsubscribe(unsubscribed)

        try library.enableNotificationsForSubscribedPodcasts()
        #expect(podcast.notificationsEnabled)
        #expect(!unsubscribed.notificationsEnabled)
    }

    /// N35
    @Test func importingOPMLTurnsNotificationsOn() async throws {
        serve(feedURL, feed([("g1", "One", "09 Oct 2026")]))
        let opml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="1.0"><head><title>Export</title></head><body>
            <outline text="One" type="rss" xmlUrl="\(feedURL.absoluteString)"/></body></opml>
            """
        _ = try await library.importOPML(Data(opml.utf8))
        let podcast = try #require(try context.fetch(FetchDescriptor<Podcast>()).first)
        #expect(podcast.notificationsEnabled)
        #expect(center.authorizationRequests == 1)
    }

    /// A47: no prompt while no subscribed podcast wants notifications.
    @Test func noPromptWithoutPodcastsThatWantNotifications() async throws {
        let podcast = Podcast(feedURL: feedURL, title: "P", subscribedAt: Self.now)
        context.insert(podcast)
        try context.save()
        let scheduler = NotificationScheduler(context: context, center: center, now: { Self.now })
        await scheduler.requestAuthorizationIfNeeded()
        #expect(center.authorizationRequests == 0)
        podcast.notificationsEnabled = true
        try context.save()
        await scheduler.requestAuthorizationIfNeeded()
        #expect(center.authorizationRequests == 1)
    }

    // MARK: Refreshing

    /// A44: the podcast refreshed longest ago loads first; with one more podcast than
    /// parallel loads, the most recently refreshed one starts last.
    @Test func refreshAllStartsWithTheLongestUnrefreshedPodcast() async throws {
        let count = FeedRefresher.maxConcurrentLoads + 1
        let urls = (0..<count).map { URL(string: "https://p\($0).example.com/feed.xml")! }
        for url in urls {
            serve(url, feed([("g1", "One", "09 Oct 2026")]))
            try await library.subscribe(to: url)
        }
        // p0 was refreshed most recently, p1 longest ago.
        for podcast in try context.fetch(FetchDescriptor<Podcast>()) {
            let index = try #require(urls.firstIndex(of: podcast.feedURL))
            podcast.lastRefreshedAt = Self.now.addingTimeInterval(index == 0 ? 0 : -Double(count - index) * 60)
        }
        try context.save()
        let before = routes.requests.count

        _ = try await refresher().refreshAll(now: Self.now)
        let requested = routes.requests.dropFirst(before).compactMap(\.url)
        #expect(requested.count == count)
        #expect(requested.last == urls[0])
    }

    /// A44: when the background time runs out, no further feeds start.
    @Test func cancelledRefreshStartsNoFeeds() async throws {
        try await subscribe()
        let before = routes.requests.count
        let refresher = refresher()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await refresher.refreshAll(now: Self.now)
        }
        let summary = try await task.value
        #expect(summary.newEpisodes.isEmpty)
        #expect(routes.requests.count == before)
    }

    /// A44: podcasts without notifications or playlists come last, however long ago they
    /// were refreshed.
    @Test func refreshAllStartsWithWatchedPodcasts() async throws {
        let count = FeedRefresher.maxConcurrentLoads + 1
        let urls = (0..<count).map { URL(string: "https://p\($0).example.com/feed.xml")! }
        for url in urls {
            serve(url, feed([("g1", "One", "09 Oct 2026")]))
            try await library.subscribe(to: url)
        }
        // p0 was refreshed longest ago, but nobody waits for it.
        for podcast in try context.fetch(FetchDescriptor<Podcast>()) {
            let index = try #require(urls.firstIndex(of: podcast.feedURL))
            podcast.lastRefreshedAt = Self.now.addingTimeInterval(-Double(count - index) * 60)
            if index == 0 { try library.setNotificationsEnabled(false, for: podcast) }
        }
        try context.save()
        let before = routes.requests.count

        _ = try await refresher().refreshAll(now: Self.now)
        let requested = routes.requests.dropFirst(before).compactMap(\.url)
        #expect(requested.count == count)
        #expect(requested.last == urls[0])
    }

    /// A44: after the budget no feed starts and running loads stop; the started ones count as
    /// attempted, so they come last next time.
    @Test func budgetEndsTheRefresh() async throws {
        let count = FeedRefresher.maxConcurrentLoads + 1
        let urls = (0..<count).map { URL(string: "https://p\($0).example.com/feed.xml")! }
        for url in urls {
            serve(url, feed([("g1", "One", "09 Oct 2026")]))
            try await library.subscribe(to: url)
            routes.set(url, .init(body: Data(feed([("g1", "One", "09 Oct 2026")]).utf8), delay: .seconds(10)))
        }
        let before = routes.requests.count
        let later = Self.now.addingTimeInterval(3600)
        let clock = ContinuousClock()
        let start = clock.now

        let summary = try await refresher().refreshAll(now: later, budget: .milliseconds(300))
        #expect(clock.now - start < .seconds(5))
        #expect(routes.requests.count - before == FeedRefresher.maxConcurrentLoads)
        #expect(summary.refreshed == 0)
        #expect(summary.skipped == count)
        let attempted = try context.fetch(FetchDescriptor<Podcast>()).filter { $0.lastRefreshedAt == later }
        #expect(attempted.count == FeedRefresher.maxConcurrentLoads)
    }

    /// "Refresh all" saves once for all feeds without new episodes, not once per feed: every
    /// save wakes the main context and every `@Query` on screen.
    @Test func refreshAllSavesUnchangedFeedsTogether() async throws {
        let count = FeedRefresher.maxConcurrentLoads + 2
        let urls = (0..<count).map { URL(string: "https://p\($0).example.com/feed.xml")! }
        for url in urls {
            serve(url, feed([("g1", "One", "09 Oct 2026")]))
            try await library.subscribe(to: url)
        }
        // Half answer "not modified", half the same feed again: no new episodes either way.
        for url in urls.prefix(count / 2) { routes.set(url, .init(status: 304)) }
        let refresher = refresher()
        let saves = SaveCounter(of: container, excluding: context)
        let later = Self.now.addingTimeInterval(3600)

        let summary = try await refresher.refreshAll(now: later)
        #expect(summary.refreshed == count)
        #expect(saves.count == 1, "saves: \(saves.count)")
        #expect(try context.fetch(FetchDescriptor<Podcast>()).allSatisfy { $0.lastRefreshedAt == later })
    }

    /// A44: a dead feed must not stay first in every run.
    @Test func failedFeedsCountAsAttempted() async throws {
        let podcast = try await subscribe()
        routes.set(feedURL, .init(status: 500))
        let later = Self.now.addingTimeInterval(3600)
        let summary = try await refresher().refreshAll(now: later)
        #expect(summary.failures == 1)
        #expect(try fresh(podcast).lastRefreshedAt == later)
    }

    /// A44: a podcast's new episodes are notified as soon as its feed is done, not after the
    /// last feed (when the background time runs out first, they would never be notified).
    @Test func newEpisodesAreNotifiedBeforeTheLastFeedIsDone() async throws {
        try await subscribe()
        let slow = URL(string: "https://slow.example.com/feed.xml")!
        serve(slow, feed([("s1", "Slow", "09 Oct 2026")]))
        try await library.subscribe(to: slow)
        routes.set(slow, .init(body: Data(feed([("s1", "Slow", "09 Oct 2026")]).utf8), delay: .seconds(3)))
        serve(feedURL, feed([("g2", "Two", "10 Oct 2026"), ("g1", "One", "09 Oct 2026")]))

        let refresh = Task { await library.refreshAll() }
        let clock = ContinuousClock()
        let giveUp = clock.now + .seconds(2)
        while center.posted.isEmpty, clock.now < giveUp { try await Task.sleep(for: .milliseconds(20)) }
        #expect(center.posted.map(\.body) == ["Two"])
        #expect(library.isRefreshing, "the slow feed is still loading")
        await refresh.value
    }

    @Test func refreshNotifiesNewEpisodes() async throws {
        let podcast = try await subscribe()
        serve(feedURL, feed([("g2", "Two", "10 Oct 2026"), ("g1", "One", "09 Oct 2026")]))
        await library.refreshAll()

        let notification = try #require(center.posted.first)
        #expect(center.posted.count == 1)
        let episode = try #require(try context.fetch(FetchDescriptor<Episode>()).first { $0.guid == "g2" })
        #expect(notification.episode == episode.uuid)
        #expect(notification.podcast == podcast.uuid)
        #expect(notification.title == "Test Podcast")
        #expect(notification.body == "Two")
        #expect(notification.category == .newEpisodeInPlaylists, "no playlists to add to")
    }

    @Test func refreshingOnePodcastNotifiesToo() async throws {
        let podcast = try await subscribe()
        serve(feedURL, feed([("g2", "Two", "10 Oct 2026"), ("g1", "One", "09 Oct 2026")]))
        try await library.refresh(podcast)
        #expect(center.posted.map(\.body) == ["Two"])
    }

    /// N34: the button shows only while an assigned playlist misses the episode.
    @Test(arguments: [(AutoAddRule.off, NotificationCategory.newEpisode), (.bottom, .newEpisodeInPlaylists)])
    func categoryDependsOnTheAssignedPlaylists(rule: AutoAddRule, category: NotificationCategory) async throws {
        let podcast = try await subscribe()
        let playlists = PlaylistService(context: context, now: { Self.now })
        let playlist = try playlists.createPlaylist(name: "L", colorKey: "blue", symbolName: "star")
        try playlists.assign(podcast, to: playlist, autoAdd: rule)

        serve(feedURL, feed([("g2", "Two", "10 Oct 2026"), ("g1", "One", "09 Oct 2026")]))
        await library.refreshAll()
        #expect(center.posted.map(\.category) == [category])
    }

    @Test func podcastsWithNotificationsOffAreNotNotified() async throws {
        let podcast = try await subscribe()
        try library.setNotificationsEnabled(false, for: podcast)
        serve(feedURL, feed([("g2", "Two", "10 Oct 2026"), ("g1", "One", "09 Oct 2026")]))
        await library.refreshAll()
        #expect(center.posted.isEmpty)
    }

    /// A45
    @Test func episodesOlderThanSevenDaysAreNotNotified() async throws {
        try await subscribe()
        serve(feedURL, feed([("g1", "One", "09 Oct 2026"), ("old", "Old", "01 Oct 2026")]))
        await library.refreshAll()
        #expect(center.posted.isEmpty)
    }

    @Test func deniedPermissionPostsNothing() async throws {
        let center = FakeNotificationCenter(authorization: .notDetermined, grants: false)
        let test = try NotificationSchedulerTests(center: center)
        try await test.subscribe()
        test.serve(test.feedURL, test.feed([("g2", "Two", "10 Oct 2026"), ("g1", "One", "09 Oct 2026")]))
        await test.library.refreshAll()
        #expect(center.posted.isEmpty)
        #expect(center.authorizationRequests == 1, "asked once, when subscribing")
    }

    // MARK: Responses

    @Test func responsesAreParsedFromTheActionAndTheEpisode() {
        let id = UUID()
        let info: [AnyHashable: Any] = [NotificationResponse.episodeKey: id.uuidString]
        #expect(NotificationResponse(actionIdentifier: "com.apple.UNNotificationDefaultActionIdentifier", userInfo: info) == .open(episode: id))
        #expect(NotificationResponse(actionIdentifier: "playNext", userInfo: info) == .action(.playNext, episode: id))
        #expect(NotificationResponse(actionIdentifier: "addToPlaylists", userInfo: info) == .action(.addToPlaylists, episode: id))
        #expect(NotificationResponse(actionIdentifier: "com.apple.UNNotificationDismissActionIdentifier", userInfo: info) == nil)
        #expect(NotificationResponse(actionIdentifier: "playLast", userInfo: [:]) == nil)
    }

    // MARK: Helpers

    @discardableResult
    private func subscribe() async throws -> Podcast {
        serve(feedURL, feed([("g1", "One", "09 Oct 2026")]))
        return try #require(try await library.subscribe(to: feedURL))
    }

    /// Counts `ModelContext.didSave` of one context while it lives (other tests save in parallel).
    private final class SaveCounter: @unchecked Sendable {
        private let state = OSAllocatedUnfairLock(initialState: 0)
        /// Only read in `deinit`.
        private let token: any NSObjectProtocol

        /// Counts the saves of every context of `container` except `main` (the refresher writes
        /// in a fresh context each time).
        init(of container: ModelContainer, excluding main: ModelContext) {
            let state = self.state
            let observed = ObjectIdentifier(container)
            let excluded = ObjectIdentifier(main)
            token = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { notification in
                guard let saved = notification.object as? ModelContext, ObjectIdentifier(saved) != excluded,
                      ObjectIdentifier(saved.container) == observed else { return }
                state.withLock { $0 += 1 }
            }
        }

        deinit { NotificationCenter.default.removeObserver(token) }

        var count: Int { state.withLock { $0 } }
    }

    private func refresher() -> FeedRefresher {
        FeedRefresher(modelContainer: container, loader: FeedLoader(session: StubURLProtocol.session(routes: routes)))
    }

    private func fresh(_ podcast: Podcast) throws -> Podcast {
        let id = podcast.uuid
        return try #require(try context.fetch(FetchDescriptor<Podcast>(predicate: #Predicate { $0.uuid == id })).first)
    }

    private func serve(_ url: URL, _ body: String) {
        routes.set(url, .init(body: Data(body.utf8)))
    }

    /// Items: (guid, title, date like "09 Oct 2026").
    private func feed(_ items: [(String, String, String)]) -> String {
        let entries = items.map { guid, title, date in
            """
            <item><guid>\(guid)</guid><title>\(title)</title><pubDate>\(date) 08:00:00 +0000</pubDate>
            <enclosure url="https://cdn.example.com/\(guid).mp3" length="1000" type="audio/mpeg"/></item>
            """
        }.joined()
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0"><channel><title>Test Podcast</title>\(entries)</channel></rss>
            """
    }
}
