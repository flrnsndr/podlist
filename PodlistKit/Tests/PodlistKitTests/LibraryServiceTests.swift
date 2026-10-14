import Foundation
import SwiftData
import Synchronization
import Testing
@testable import PodlistKit

/// Integration tests: subscribing, refreshing, unsubscribing and played status with an
/// in-memory store and a stubbed network (concept §9, level 2).
@MainActor
struct LibraryServiceTests {
    private let container: ModelContainer
    private let routes = StubURLProtocol.Routes()
    private let service: LibraryService
    private var context: ModelContext { container.mainContext }
    private nonisolated static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)
    private let feedURL = URL(string: "https://example.com/feed.xml")!

    init() throws {
        container = try PodlistStore.makeContainer(inMemory: true)
        service = LibraryService(
            container: container, loader: FeedLoader(session: StubURLProtocol.session(routes: routes)),
            now: { LibraryServiceTests.now })
    }

    // MARK: Subscribing and refreshing

    @Test func subscribingStoresThePodcastWithItsEpisodes() async throws {
        serve(feedURL, feed(items: [("g2", "Two", 2), ("g1", "One", 1)]))
        let podcast = try #require(try await service.subscribe(to: feedURL))
        #expect(podcast.title == "Test Podcast")
        #expect(podcast.isSubscribed)
        #expect(podcast.etag == "\"v1\"")
        #expect(Set(podcast.episodes?.map(\.guid) ?? []) == ["g1", "g2"])
        #expect(podcast.episodes?.first { $0.guid == "g1" }?.duration == 1_800)
    }

    @Test func subscribingTwiceKeepsOnePodcast() async throws {
        serve(feedURL, feed(items: [("g1", "One", 1)]))
        let first = try await service.subscribe(to: feedURL)
        let second = try await service.subscribe(to: URL(string: "http://example.com/feed.xml")!)
        #expect(first?.uuid == second?.uuid)
        #expect(try context.fetchCount(FetchDescriptor<Podcast>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Episode>()) == 1)
    }

    @Test func refreshAddsNewEpisodesAndKeepsListeningState() async throws {
        serve(feedURL, feed(items: [("g1", "One", 1)]))
        let podcast = try #require(try await service.subscribe(to: feedURL))
        let episode = try #require(podcast.episodes?.first)
        try service.saveProgress(episode, position: 120)

        serve(feedURL, feed(items: [("g2", "Two", 2), ("g1", "One (updated)", 1)]), etag: "\"v2\"")
        try await service.refresh(podcast)

        let episodes = try context.fetch(FetchDescriptor<Episode>(sortBy: [SortDescriptor(\.publishedAt)]))
        #expect(episodes.map(\.guid) == ["g1", "g2"])
        #expect(episodes[0].title == "One (updated)")
        #expect(episodes[0].playbackPosition == 120)
        #expect(try fresh(podcast).etag == "\"v2\"")
    }

    @Test func refreshAddsNewEpisodesToAssignedPlaylists() async throws {
        serve(feedURL, feed(items: [("g1", "One", 1)]))
        let podcast = try #require(try await service.subscribe(to: feedURL))
        let playlists = PlaylistService(context: context, now: { LibraryServiceTests.now })
        let top = try playlists.createPlaylist(name: "Top", colorKey: "blue", symbolName: "star")
        let bottom = try playlists.createPlaylist(name: "Bottom", colorKey: "blue", symbolName: "star")
        let off = try playlists.createPlaylist(name: "Off", colorKey: "blue", symbolName: "star")
        try playlists.setAssignments(of: podcast, to: [top.uuid: .top, bottom.uuid: .bottom, off.uuid: .off])

        serve(feedURL, feed(items: [("g3", "Three", 3), ("g2", "Two", 2), ("g1", "One", 1)]), etag: "\"v2\"")
        try await service.refresh(podcast)

        func titles(_ playlist: Playlist) throws -> [String] {
            let id = playlist.uuid
            let fresh = try #require(try context.fetch(FetchDescriptor<Playlist>(predicate: #Predicate { $0.uuid == id })).first)
            return fresh.sortedEntries.compactMap { $0.episode?.title }
        }
        #expect(try titles(top) == ["Three", "Two"], "newest on top")
        #expect(try titles(bottom) == ["Two", "Three"], "in order of publication at the bottom")
        #expect(try titles(off).isEmpty)
        let entries = try context.fetch(FetchDescriptor<PlaylistEntry>())
        #expect(entries.filter { $0.episode?.title == "Three" }.allSatisfy { $0.origin == .automatic })
    }

    @Test func refreshSendsValidatorsAndAcceptsNotModified() async throws {
        serve(feedURL, feed(items: [("g1", "One", 1)]))
        let podcast = try #require(try await service.subscribe(to: feedURL))
        routes.set(feedURL, .init(status: 304))
        try await service.refresh(podcast)
        #expect(routes.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(try context.fetchCount(FetchDescriptor<Episode>()) == 1)
    }

    @Test func permanentRedirectMovesTheFeedURL() async throws {
        serve(feedURL, feed(items: [("g1", "One", 1)]))
        let podcast = try #require(try await service.subscribe(to: feedURL))
        let moved = URL(string: "https://new.example.com/feed.xml")!
        routes.set(feedURL, .init(status: 301, redirect: moved))
        serve(moved, feed(items: [("g1", "One", 1)]))
        try await service.refresh(podcast)
        #expect(try fresh(podcast).feedURL == moved)
    }

    @Test func newFeedURLInTheFeedMovesTheFeedURL() async throws {
        let moved = URL(string: "https://new.example.com/feed.xml")!
        serve(feedURL, feed(items: [("g1", "One", 1)], newFeedURL: moved))
        let podcast = try #require(try await service.subscribe(to: feedURL))
        #expect(podcast.feedURL == moved)
    }

    @Test func refreshAllRefreshesSubscribedPodcastsOnly() async throws {
        let other = URL(string: "https://other.example.com/feed.xml")!
        serve(feedURL, feed(items: [("g1", "One", 1)]))
        serve(other, feed(items: [("o1", "Other", 1)]))
        try await service.subscribe(to: feedURL)
        let unsubscribed = try #require(try await service.subscribe(to: other))
        try service.unsubscribe(unsubscribed)

        serve(feedURL, feed(items: [("g2", "Two", 2), ("g1", "One", 1)]))
        serve(other, feed(items: [("o2", "Other 2", 2), ("o1", "Other", 1)]))
        await service.refreshAll()
        let guids = Set(try context.fetch(FetchDescriptor<Episode>()).map(\.guid))
        #expect(guids == ["g1", "g2"])
    }

    /// A63: returning to the app refreshes once the last complete refresh is 15 minutes old.
    @Test func returningRefreshesOnlyWhenDue() async throws {
        let clock = TestClock(Self.now)
        let service = LibraryService(
            container: container, loader: FeedLoader(session: StubURLProtocol.session(routes: routes)), now: { clock.now })
        serve(feedURL, feed(items: [("g1", "One", 1)]))
        try await service.subscribe(to: feedURL)
        let start = routes.requests.count

        await service.refreshAllIfDue()
        #expect(routes.requests.count == start + 1, "no complete refresh in this app run yet")
        clock.advance(by: 14 * 60)
        await service.refreshAllIfDue()
        #expect(routes.requests.count == start + 1)
        clock.advance(by: 60)
        await service.refreshAllIfDue()
        #expect(routes.requests.count == start + 2)
    }

    /// A63: a background run cut short by its budget is no complete refresh.
    @Test func refreshCutShortIsNotComplete() async throws {
        serve(feedURL, feed(items: [("g1", "One", 1)]))
        try await service.subscribe(to: feedURL)
        routes.set(feedURL, .init(body: Data(feed(items: [("g1", "One", 1)]).utf8), delay: .seconds(10)))
        await service.refreshAll(budget: .milliseconds(200))

        serve(feedURL, feed(items: [("g1", "One", 1)]))
        let before = routes.requests.count
        await service.refreshAllIfDue()
        #expect(routes.requests.count == before + 1)
    }

    // MARK: Unsubscribing (concept §4.9)

    /// A42: the cached chapter images of deleted episodes go too.
    @Test func unsubscribingDeletesTheChapterImagesOfDeletedEpisodes() async throws {
        let images = ChapterImageStore(directory: URL.temporaryDirectory.appending(path: "LibraryServiceTests-\(UUID().uuidString)"))
        let service = LibraryService(
            container: container, loader: FeedLoader(session: StubURLProtocol.session(routes: routes)),
            chapterImages: images, now: { LibraryServiceTests.now })
        serve(feedURL, feed(items: [("g1", "E1", 1), ("g2", "E2", 2)]))
        let podcast = try #require(try await service.subscribe(to: feedURL))
        let byGUID = Dictionary(uniqueKeysWithValues: (podcast.episodes ?? []).map { ($0.guid, $0) })
        let deleted = try #require(byGUID["g1"])
        let kept = try #require(byGUID["g2"])
        try service.saveProgress(kept, position: 60)
        let deletedImage = try images.save(Data([1]), episode: deleted.uuid, index: 0)
        let keptImage = try images.save(Data([2]), episode: kept.uuid, index: 0)

        try service.unsubscribe(podcast)
        #expect(images.data(forCached: deletedImage) == nil)
        #expect(images.data(forCached: keptImage) == Data([2]))
    }

    @Test func unsubscribingKeepsOnlyEpisodesThatAreStillNeeded() async throws {
        serve(feedURL, feed(items: (1...6).map { ("g\($0)", "E\($0)", $0) }))
        let podcast = try #require(try await service.subscribe(to: feedURL))
        let byGUID = Dictionary(uniqueKeysWithValues: (podcast.episodes ?? []).map { ($0.guid, $0) })
        let playlist = Playlist(colorKey: "blue", symbolName: "star", displayOrder: 0)
        context.insert(playlist)
        context.insert(PlaylistAssignment(podcast: podcast, playlist: playlist, autoAdd: .top, createdAt: Self.now))
        context.insert(PlaylistEntry(playlist: playlist, episode: try #require(byGUID["g1"]), position: 0, addedAt: Self.now, origin: .manual))
        context.insert(QueueItem(position: 0, episode: try #require(byGUID["g2"])))
        let inHistory = try #require(byGUID["g3"])
        context.insert(try UpNextSnapshot(UpNextSnapshotValue(
            createdAt: Self.now, reason: .cleared, state: UpNextState(items: [.episode(EpisodeID(inHistory.uuid))]))))
        try service.markPlayed(try #require(byGUID["g4"]))
        try service.saveProgress(try #require(byGUID["g5"]), position: 60)

        try service.unsubscribe(podcast)

        #expect(!podcast.isSubscribed)
        #expect(try context.fetchCount(FetchDescriptor<PlaylistAssignment>()) == 0)
        let kept = Set(try context.fetch(FetchDescriptor<Episode>()).map(\.guid))
        #expect(kept == ["g1", "g2", "g3", "g4", "g5"])
    }

    /// N98, A78: an episode auto-added by a refresh comes first in "Alles".
    @Test func anAutoAddedEpisodeBecomesTheResumePointOfEverything() async throws {
        serve(feedURL, feed(items: [("g1", "One", 1)]))
        let podcast = try #require(try await service.subscribe(to: feedURL))
        let playlists = PlaylistService(context: context, now: { LibraryServiceTests.now })
        try playlists.ensureEverything()
        let list = try playlists.createPlaylist(name: "L", colorKey: "blue", symbolName: "star")
        try playlists.assign(podcast, to: list, autoAdd: .top)
        try playlists.add(try #require(podcast.episodes?.first), to: list)
        let everything = try #require(try context.fetch(FetchDescriptor<Playlist>()).first(where: \.isEverything))
        everything.resumeEpisode = podcast.episodes?.first
        try context.save()

        serve(feedURL, feed(items: [("g2", "Two", 2), ("g1", "One", 1)]), etag: "\"v2\"")
        try await service.refresh(podcast)
        #expect(everything.resumeEpisode?.guid == "g2")
    }

    /// "Refresh all" with new episodes of several podcasts: Alles starts at the top one of
    /// them, not at the podcast whose feed happened to finish last (A78).
    @Test func refreshingAllPutsEverythingsCursorOnTheTopNewEpisode() async throws {
        let otherURL = URL(string: "https://example.com/other.xml")!
        serve(feedURL, feed(items: [("p1", "P1", 1)]))
        serve(otherURL, feed(items: [("q1", "Q1", 1)]))
        let p = try #require(try await service.subscribe(to: feedURL))
        let q = try #require(try await service.subscribe(to: otherURL))
        let playlists = PlaylistService(context: context, now: { LibraryServiceTests.now })
        try playlists.ensureEverything()
        let list = try playlists.createPlaylist(name: "L", colorKey: "blue", symbolName: "star")
        try playlists.assign(p, to: list, autoAdd: .top)
        try playlists.assign(q, to: list, autoAdd: .top)

        serve(feedURL, feed(items: [("p2", "P2", 2), ("p1", "P1", 1)]), etag: "\"v2\"")
        serve(otherURL, feed(items: [("q2", "Q2", 2), ("q1", "Q1", 1)]), etag: "\"v2\"")
        await service.refreshAll()
        let all = try context.fetch(FetchDescriptor<Playlist>())
        let everything = try #require(all.everything)
        let shown = everything.shownEpisodes(among: all)
        #expect(Set(shown.map(\.guid)) == ["p2", "q2"])
        #expect(everything.resumeEpisode == shown.first)
    }

    /// The short description is stored, updated and cleared with the feed (concept §4.12, N83).
    @Test func refreshKeepsTheShortDescriptionCurrent() async throws {
        serve(feedURL, feed(items: [("g1", "One", 1)], itemExtra: "<itunes:subtitle>Erste</itunes:subtitle>"))
        let podcast = try #require(try await service.subscribe(to: feedURL))
        #expect(podcast.episodes?.first?.subtitle == "Erste")

        serve(feedURL, feed(items: [("g1", "One", 1)], itemExtra: "<itunes:subtitle>Neu</itunes:subtitle>"), etag: "\"v2\"")
        try await service.refresh(podcast)
        #expect(try context.fetch(FetchDescriptor<Episode>()).map(\.subtitle) == ["Neu"])

        serve(feedURL, feed(items: [("g1", "One", 1)]), etag: "\"v3\"")
        try await service.refresh(podcast)
        #expect(try context.fetch(FetchDescriptor<Episode>()).map(\.subtitle) == [nil])
    }

    /// The listening history filters by the last known playlists (concept §4.12, N85, A74).
    @Test func unsubscribingRemembersThePodcastsPlaylists() async throws {
        serve(feedURL, feed(items: [("g1", "E1", 1)]))
        let podcast = try #require(try await service.subscribe(to: feedURL))
        let sport = Playlist(customName: "Sport", colorKey: "green", symbolName: "figure.run", displayOrder: 0)
        let news = Playlist(customName: "News", colorKey: "red", symbolName: "newspaper", displayOrder: 1)
        context.insert(sport)
        context.insert(news)
        context.insert(PlaylistAssignment(podcast: podcast, playlist: sport, autoAdd: .top, createdAt: Self.now))
        context.insert(PlaylistAssignment(podcast: podcast, playlist: news, autoAdd: .off, createdAt: Self.now))
        try context.save()

        try service.unsubscribe(podcast)

        #expect(Set(podcast.playlistUUIDsBeforeUnsubscribing) == [sport.uuid, news.uuid])
        #expect(podcast.assignments?.isEmpty ?? true)
    }

    @Test func subscribingAgainBringsBackThePodcastWithItsListeningState() async throws {
        serve(feedURL, feed(items: [("g2", "Two", 2), ("g1", "One", 1)]))
        let podcast = try #require(try await service.subscribe(to: feedURL))
        try service.saveProgress(try #require(podcast.episodes?.first { $0.guid == "g1" }), position: 60)
        try service.unsubscribe(podcast)
        #expect(try context.fetchCount(FetchDescriptor<Episode>()) == 1)

        let again = try #require(try await service.subscribe(to: feedURL))
        #expect(again.uuid == podcast.uuid)
        #expect(again.isSubscribed)
        let episodes = try context.fetch(FetchDescriptor<Episode>())
        #expect(Set(episodes.map(\.guid)) == ["g1", "g2"])
        #expect(episodes.first { $0.guid == "g1" }?.playbackPosition == 60)
    }

    // MARK: OPML import

    @Test func opmlImportSubscribesNewFeedsAndReportsFailuresWithReasons() async throws {
        let second = URL(string: "https://two.example.com/feed.xml")!
        let broken = URL(string: "https://broken.example.com/feed.xml")!
        let gone = URL(string: "https://gone.example.com/feed.xml")!
        let html = URL(string: "https://html.example.com/feed.xml")!
        let unknownHost = URL(string: "https://nowhere.example.com/feed.xml")!
        serve(feedURL, feed(items: [("g1", "One", 1)]))
        serve(second, feed(items: [("s1", "Second", 1)]))
        routes.set(broken, .init(status: 500))
        routes.set(gone, .init(status: 404))
        routes.set(html, .init(body: Data("<!DOCTYPE html><html><body>Moved</body></html>".utf8)))
        try await service.subscribe(to: feedURL)

        let opml = """
            <?xml version="1.0" encoding="UTF-8"?>
            <opml version="1.0"><head><title>Export</title></head><body>
            <outline text="One" type="rss" xmlUrl="\(feedURL.absoluteString)"/>
            <outline text="Two" type="rss" xmlUrl="\(second.absoluteString)"/>
            <outline text="Broken" type="rss" xmlUrl="\(broken.absoluteString)"/>
            <outline text="Gone" type="rss" xmlUrl="\(gone.absoluteString)"/>
            <outline text="HTML" type="rss" xmlUrl="\(html.absoluteString)"/>
            <outline text="Nowhere" type="rss" xmlUrl="\(unknownHost.absoluteString)"/>
            </body></opml>
            """
        let result = try await service.importOPML(Data(opml.utf8))
        #expect(result.subscribed == 1)
        #expect(result.alreadySubscribed == 1)
        // In the file's order, each with its reason.
        #expect(result.failed.map(\.outline.feedURL) == [broken, gone, html, unknownHost])
        #expect(result.failed.map(\.reason) == [.httpStatus(500), .notFound, .notAFeed, .serverNotFound])
        #expect(service.importProgress == nil)
        #expect(try context.fetchCount(FetchDescriptor<Podcast>()) == 2)
    }

    // MARK: Played status and position (concept §4.3, A8, N9)

    @Test func playedStatusAndPositionFollowTheRules() async throws {
        serve(feedURL, feed(items: [("g1", "One", 1)]))
        let podcast = try #require(try await service.subscribe(to: feedURL))
        let episode = try #require(podcast.episodes?.first)  // 1800 s

        try service.saveProgress(episode, position: 1_000)
        #expect(!episode.isPlayed && episode.playbackPosition == 1_000)

        try service.saveProgress(episode, position: 1_780)
        #expect(episode.isPlayed, "near the end counts as played")
        #expect(episode.playbackPosition == 1_780, "the position stays (A8)")

        #expect(try service.playbackWillStart(episode) == 0, "a played episode starts over (N23)")
        #expect(!episode.isPlayed, "starting a played episode by hand makes it unplayed (N9)")
        try service.saveProgress(episode, position: 600)
        #expect(try service.playbackWillStart(episode) == 600, "re-listening and interrupted: it goes on there (A8)")

        try service.episodeDidEnd(episode)
        #expect(episode.isPlayed && episode.playbackPosition == 0)

        try service.saveProgress(episode, position: 300)
        try service.markPlayed(episode)
        #expect(episode.isPlayed && episode.playbackPosition == 0, "marking played starts over (A8)")
        try service.markUnplayed(episode)
        #expect(!episode.isPlayed)
    }

    @Test func playbackStartsOverWhenThePositionIsAtTheEnd() async throws {
        serve(feedURL, feed(items: [("g1", "One", 1)]))
        let episode = try #require(try await service.subscribe(to: feedURL)?.episodes?.first)
        episode.playbackPosition = 1_800
        #expect(try service.playbackWillStart(episode) == 0)
    }

    // MARK: Per-podcast player settings (Slice 4: speed N25, intro A28, outro N28)

    @Test func introIsSkippedWhenPlaybackWouldStartInIt() async throws {
        serve(feedURL, feed(items: [("g1", "One", 1)]))
        let podcast = try #require(try await service.subscribe(to: feedURL))
        let episode = try #require(podcast.episodes?.first)
        try service.setSkipIntro(45, for: podcast)
        #expect(service.startPosition(of: episode) == 45)
        #expect(try service.playbackWillStart(episode) == 45)
        try service.saveProgress(episode, position: 600)
        #expect(try service.playbackWillStart(episode) == 600)
        try service.episodeDidEnd(episode)
        #expect(try service.playbackWillStart(episode) == 45, "a played episode starts over after the intro")
    }

    @Test func podcastSettingsAreStoredAndClamped() async throws {
        serve(feedURL, feed(items: [("g1", "One", 1)]))
        let podcast = try #require(try await service.subscribe(to: feedURL))
        try service.setPlaybackSpeed(1.47, for: podcast)
        #expect(podcast.playbackSpeed == 1.5)
        try service.setPlaybackSpeed(nil, for: podcast)
        #expect(podcast.playbackSpeed == nil, "nil = the global speed")
        try service.setSkipIntro(-5, for: podcast)
        try service.setSkipOutro(90, for: podcast)
        #expect(podcast.skipIntroSeconds == 0)
        #expect(podcast.skipOutroSeconds == 90)
    }

    /// ADR 0005: Podlove chapters from a refresh replace weaker sources, never JSON chapters.
    @Test func podloveChaptersFromTheFeedFollowTheSourcePriority() async throws {
        let chapters = "<psc:chapters version=\"1.2\"><psc:chapter start=\"00:00:00\" title=\"Intro\"/><psc:chapter start=\"00:10:00\" title=\"Thema\"/></psc:chapters>"
        serve(feedURL, feed(items: [("g1", "One", 1)], itemExtra: chapters))
        let podcast = try #require(try await service.subscribe(to: feedURL))
        let episode = try #require(podcast.episodes?.first)
        #expect(episode.chaptersSource == .podlove)
        #expect(episode.chapters.map(\.end) == [600, 1_800], "normalized")

        episode.chaptersSource = .shownotes
        try context.save()
        serve(feedURL, feed(items: [("g1", "One", 1)], itemExtra: chapters), etag: "\"v2\"")
        try await service.refresh(podcast)
        #expect(try context.fetch(FetchDescriptor<Episode>()).first?.chaptersSource == .podlove, "Podlove beats show notes")

        let json = [Chapter(start: 0, end: 1_800, title: "JSON")]
        episode.chapters = json
        episode.chaptersSource = .json
        try context.save()
        serve(feedURL, feed(items: [("g1", "One", 1)], itemExtra: chapters), etag: "\"v3\"")
        try await service.refresh(podcast)
        let refreshed = try #require(try context.fetch(FetchDescriptor<Episode>()).first)
        #expect(refreshed.chaptersSource == .json)
        #expect(refreshed.chapters == json)
    }

    @Test func realDurationReplacesTheFeedValue() async throws {
        serve(feedURL, feed(items: [("g1", "One", 1)]))
        let episode = try #require(try await service.subscribe(to: feedURL)?.episodes?.first)
        try service.updateDuration(episode, to: 1_830.4)
        #expect(episode.duration == 1_830.4)
        serve(feedURL, feed(items: [("g1", "One", 1)]), etag: "\"v2\"")
        try await service.refresh(try #require(episode.podcast))
        #expect(episode.duration == 1_830.4, "a refresh does not overwrite the measured duration")
    }

    // MARK: Helpers

    /// The feed refresher writes in its own context; the main context merges those changes
    /// on the next fetch (or run loop turn).
    private func fresh(_ podcast: Podcast) throws -> Podcast {
        let id = podcast.uuid
        return try #require(try context.fetch(FetchDescriptor<Podcast>(predicate: #Predicate { $0.uuid == id })).first)
    }

    private func serve(_ url: URL, _ body: String, etag: String = "\"v1\"") {
        routes.set(url, .init(headers: ["ETag": etag], body: Data(body.utf8)))
    }

    /// Items: (guid, title, day). Each episode is 30 minutes long.
    private func feed(items: [(String, String, Int)], newFeedURL: URL? = nil, itemExtra: String = "") -> String {
        let entries = items.map { guid, title, day in
            """
            <item><guid>\(guid)</guid><title>\(title)</title>
            <pubDate>\(String(format: "%02d", day)) Oct 2026 08:00:00 +0000</pubDate>
            <itunes:duration>30:00</itunes:duration>
            <enclosure url="https://cdn.example.com/\(guid).mp3" length="1000" type="audio/mpeg"/>\(itemExtra)</item>
            """
        }.joined()
        let moved = newFeedURL.map { "<itunes:new-feed-url>\($0.absoluteString)</itunes:new-feed-url>" } ?? ""
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:psc="http://podlove.org/simple-chapters"><channel>
            <title>Test Podcast</title>\(moved)\(entries)</channel></rss>
            """
    }
}

/// A clock the test moves forward by hand.
private final class TestClock: Sendable {
    private let date: Mutex<Date>

    init(_ date: Date) { self.date = Mutex(date) }

    var now: Date { date.withLock { $0 } }
    func advance(by interval: TimeInterval) { date.withLock { $0 += interval } }
}
