import Foundation
import SwiftData
import Testing
@testable import PodlistKit

/// The playlist "Alles" with SwiftData, Up Next and the real player (concept §4.1, N70–N73).
@MainActor
struct EverythingServiceTests {
    private let container: ModelContainer
    private let library: LibraryService
    private let playlists: PlaylistService
    private let player: PlayerController
    private let upNext: UpNextService
    private var context: ModelContext { container.mainContext }
    private nonisolated static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)

    init() throws {
        container = try PodlistStore.makeContainer(inMemory: true)
        // Every add gets a later date, so "Hinzugefügt" orders the episodes as they were added.
        let clock = StepClock(start: Self.now)
        library = LibraryService(container: container, now: { Self.now })
        playlists = PlaylistService(context: container.mainContext, now: { clock.next() })
        player = PlayerController(library: library)
        upNext = UpNextService(context: container.mainContext, library: library, player: player, now: { clock.next() })
    }

    // MARK: Creating

    @Test func everythingIsCreatedOnceFirstAndWithoutTheHiddenPlaylists() throws {
        try playlists.insertDefaultPlaylists()
        let news = try playlist(key: "news")
        try playlists.setHidden(true, of: news)
        news.isExcludedFromEverything = false  // a store from before "Alles" (A65)
        try playlists.ensureEverything()
        try playlists.ensureEverything()

        let all = try context.fetch(FetchDescriptor<Playlist>(sortBy: [SortDescriptor(\.displayOrder)]))
        #expect(all.count(where: \.isEverything) == 1)
        let everything = try #require(all.first)
        #expect(everything.isEverything)
        #expect(everything.sort == Everything.sort && everything.sortAscending == Everything.sortAscending)
        #expect(everything.playedPolicy == .remove)
        #expect(news.isExcludedFromEverything, "playlists hidden before Alles existed are left out (A65)")
        #expect(all.tags.count == DefaultPlaylist.allCases.count)
        #expect(all.tags.allSatisfy { !$0.isEverything })
    }

    @Test func everythingCannotBeDeletedOrFilledByHand() throws {
        let everything = try makeEverything()
        let (_, e) = insertPodcast("P", episodes: 1)
        try playlists.add(e[0], to: everything)
        #expect((everything.entries ?? []).isEmpty, "Alles has no entries of its own")
        try playlists.delete(everything)
        #expect(try context.fetch(FetchDescriptor<Playlist>()).contains(everything))
        try playlists.setSort(.manual, ascending: true, of: everything)
        try playlists.setSort(.published, ascending: true, of: everything)
        #expect(everything.sort == .added && !everything.sortAscending, "the sort is fixed (N97)")
    }

    /// N97: a store from before keeps whatever "Alles" was sorted by; the next launch fixes it.
    @Test func anEverythingWithAnotherSortGetsTheFixedOne() throws {
        let everything = try makeEverything()
        everything.sort = .published
        everything.sortAscending = true
        let a = try playlists.createPlaylist(name: "A", colorKey: "green", symbolName: "star")
        let (_, e) = insertPodcast("P", episodes: 1)
        try playlists.add(e[0], to: a)
        try playlists.ensureEverything()
        #expect(everything.sort == .added && !everything.sortAscending)
        #expect(everything.resumeEpisode == nil, "it starts at the newest episode (A78)")
    }

    // MARK: Content

    /// N97: newest added first; an episode added again counts with its latest entry.
    @Test func everythingShowsEachEpisodeOfThePlaylistsOnceNewestAddedFirst() throws {
        let everything = try makeEverything()
        let sport = try playlists.createPlaylist(name: "Sport", colorKey: "green", symbolName: "star")
        let politics = try playlists.createPlaylist(name: "Politik", colorKey: "red", symbolName: "star")
        let (_, e) = insertPodcast("P", episodes: 3)
        try playlists.add(e[1], to: sport)
        try playlists.add(e[0], to: politics)
        try playlists.add(e[1], to: politics)
        try playlists.add(e[2], to: sport)
        #expect(try shown(everything) == ["P2", "P1", "P0"])
    }

    /// N71: a playlist left out takes only the episodes that are in no other chosen playlist
    /// with it; a podcast left out is gone entirely.
    @Test func leavingOutPlaylistsAndPodcasts() throws {
        let everything = try makeEverything()
        let sport = try playlists.createPlaylist(name: "Sport", colorKey: "green", symbolName: "star")
        let politics = try playlists.createPlaylist(name: "Politik", colorKey: "red", symbolName: "star")
        let (p, e) = insertPodcast("P", episodes: 2)
        let (_, q) = insertPodcast("Q", episodes: 1)
        try playlists.add(e[0], to: sport)
        try playlists.add(e[0], to: politics)
        try playlists.add(e[1], to: politics)
        try playlists.add(q[0], to: politics)

        try playlists.setExcluded(true, playlist: politics)
        #expect(try shown(everything) == ["P0"])
        try playlists.setExcluded(true, podcast: p)
        #expect(try shown(everything) == [])
        try playlists.setExcluded(false, playlist: politics)
        #expect(try shown(everything) == ["Q0"])
        try playlists.setExcluded(false, podcast: p)
        #expect(try shown(everything) == ["Q0", "P1", "P0"])
    }

    /// N72, A65: hiding a playlist leaves it out of Alles, showing it again takes it back.
    @Test func hidingAPlaylistLeavesItOut() throws {
        _ = try makeEverything()
        let kids = try playlists.createPlaylist(name: "Kinder", colorKey: "pink", symbolName: "star")
        try playlists.setHidden(true, of: kids)
        #expect(kids.isExcludedFromEverything)
        try playlists.setExcluded(false, playlist: kids)
        #expect(kids.isHidden && !kids.isExcludedFromEverything, "it can be chosen again in Alles")
        try playlists.setHidden(false, of: kids)
        try playlists.setHidden(true, of: kids)
        try playlists.setHidden(false, of: kids)
        #expect(!kids.isExcludedFromEverything)
    }

    /// N99: Alles always removes played episodes, also those a keep playlist still has.
    @Test func everythingAlwaysRemovesPlayedEpisodes() throws {
        let everything = try makeEverything()
        let keep = try playlists.createPlaylist(name: "Behalten", colorKey: "green", symbolName: "star")
        try playlists.setPlayedPolicy(.keep, of: keep)
        let (_, e) = insertPodcast("P", episodes: 2)
        try playlists.add(e[0], to: keep)
        try playlists.add(e[1], to: keep)
        try library.markPlayed(e[0])
        #expect(try shown(everything) == ["P1"])
        try playlists.setPlayedPolicy(.keep, of: everything)
        #expect(everything.playedPolicy == .remove)
        #expect(try shown(everything) == ["P1"])
    }

    /// N99: a store from before may have a keep Alles; the next launch fixes it.
    @Test func aKeepEverythingBecomesRemove() throws {
        let everything = try makeEverything()
        everything.playedPolicy = .keep
        try playlists.ensureEverything()
        #expect(everything.playedPolicy == .remove)
    }

    // MARK: Up Next (taken over like any playlist, A87)

    @Test func playingEverythingPlaysThePlaylistsAndTheirPlayedPolicyApplies() throws {
        let everything = try makeEverything()
        let a = try playlists.createPlaylist(name: "A", colorKey: "green", symbolName: "star")
        let b = try playlists.createPlaylist(name: "B", colorKey: "red", symbolName: "star")
        let (_, e) = insertPodcast("P", episodes: 3)
        try playlists.add(e[2], to: a)
        try playlists.add(e[1], to: b)
        try playlists.add(e[0], to: a)
        try playlists.add(e[0], to: b)

        upNext.playNow(everything)
        #expect(player.episode == e[0])
        #expect(try queued() == [e[1], e[2]])
        player.currentItemDidEnd()
        #expect(player.episode == e[1])
        #expect((e[0].playlistEntries ?? []).isEmpty, "the played policy of A and B removed it")
        #expect(a.resumeEpisode == nil && b.resumeEpisode == nil, "Up Next never touches the other playlists")
        player.currentItemDidEnd()
        player.currentItemDidEnd()
        #expect(player.episode == nil)
        #expect(try shown(everything) == [])
    }

    /// Removed by hand from its last playlist, the episode leaves Alles but stays in the
    /// queue (A88): the taken-over queue is the user's.
    @Test func removingTheRunningEpisodeFromItsLastPlaylistLeavesTheQueueAlone() throws {
        let everything = try makeEverything()
        let a = try playlists.createPlaylist(name: "A", colorKey: "green", symbolName: "star")
        let b = try playlists.createPlaylist(name: "B", colorKey: "red", symbolName: "star")
        let (_, e) = insertPodcast("P", episodes: 2)
        try playlists.add(e[1], to: a)
        try playlists.add(e[0], to: a)
        try playlists.add(e[0], to: b)

        upNext.playNow(everything)
        try playlists.remove(e[0], from: a)
        try playlists.remove(e[0], from: b)
        #expect(try shown(everything) == ["P1"])
        #expect(player.episode == e[0])
        player.currentItemDidEnd()
        #expect(player.episode == e[1])
    }

    /// Replaced while queued, Alles remembers its frontmost episode (N107); one that left
    /// Alles meanwhile does not count, Alles starts at the top.
    @Test func everythingRemembersWhereItWasUnlessTheEpisodeLeft() throws {
        let everything = try makeEverything()
        let a = try playlists.createPlaylist(name: "A", colorKey: "green", symbolName: "star")
        let b = try playlists.createPlaylist(name: "B", colorKey: "red", symbolName: "star")
        let (p, e) = insertPodcast("P", episodes: 2)
        let (_, q) = insertPodcast("Q", episodes: 1)
        let (_, r) = insertPodcast("R", episodes: 1)
        try playlists.setExcluded(true, playlist: b)  // B is not part of Alles
        try playlists.add(r[0], to: b)
        for episode in [q[0], e[1], e[0]] { try playlists.add(episode, to: a) }  // Alles: P0, P1, Q0
        upNext.playNow(everything)
        upNext.playNow(b)
        #expect(everything.resumeEpisode == e[0])

        try playlists.setExcluded(true, podcast: p)
        upNext.playNow(everything)
        #expect(player.episode == q[0])
    }

    /// "Als Nächstes" on an episode further down in the running Alles: it plays after the
    /// running one, then Alles goes on.
    @Test func playNextFromTheRunningEverything() throws {
        let everything = try makeEverything()
        let a = try playlists.createPlaylist(name: "A", colorKey: "green", symbolName: "star")
        let (_, e) = insertPodcast("P", episodes: 4)
        for episode in e.reversed() { try playlists.add(episode, to: a) }

        upNext.playNow(everything)
        upNext.playNext(e[3])
        player.currentItemDidEnd()
        #expect(player.episode == e[3])
        player.currentItemDidEnd()
        #expect(player.episode == e[1])
    }

    // MARK: New episodes wait in the draft (A86, A87)

    @Test func anEpisodeAddedWhileEverythingPlaysWaitsInTheDraft() throws {
        let everything = try makeEverything()
        let a = try playlists.createPlaylist(name: "A", colorKey: "green", symbolName: "star")
        let (_, e) = insertPodcast("P", episodes: 3)
        try playlists.add(e[1], to: a)
        try playlists.add(e[0], to: a)
        upNext.playNow(everything)
        #expect(player.episode == e[0])

        try playlists.add(e[2], to: a)
        #expect(player.episode == e[0], "the running episode plays on")
        #expect(try queued() == [e[1]], "the queue is not told (A86)")
        #expect(try shown(everything) == ["P2", "P0", "P1"], "newest added first in Alles (N97)")
        let parts = upNext.split(of: everything, among: try context.fetch(Playlist.allWithEntries()))
        #expect(parts.live == [e[0], e[1]])
        #expect(parts.draft == [e[2]])
        player.currentItemDidEnd()
        player.currentItemDidEnd()
        #expect(player.episode == nil)
        upNext.playNow(everything)
        #expect(player.episode == e[2], "next time Alles starts at the newest episode")
    }

    /// A playlist left out of Alles does not change it.
    @Test func anEpisodeAddedToAPlaylistLeftOutChangesNothing() throws {
        let everything = try makeEverything()
        let a = try playlists.createPlaylist(name: "A", colorKey: "green", symbolName: "star")
        let hidden = try playlists.createPlaylist(name: "H", colorKey: "red", symbolName: "star")
        try playlists.setHidden(true, of: hidden)
        let (_, e) = insertPodcast("P", episodes: 3)
        for episode in e { try playlists.add(episode, to: a) }  // Alles: P2, P1, P0
        try playlists.add(e[0], to: hidden)
        #expect(try shown(everything) == ["P2", "P1", "P0"])
    }

    // MARK: Statistics

    /// A66: "Alles" is no category; a session from it counts like a single episode.
    @Test func statisticsCountEverythingLikeASingleEpisode() throws {
        let everything = try makeEverything()
        let session = ListeningSession(episodeUUID: UUID(), startedAt: Self.now)
        session.playlistUUID = everything.uuid
        context.insert(session)
        try context.save()
        let stats = ListeningStatsService(context: context, now: { Self.now })
        stats.reload()
        #expect(stats.records.map(\.playlist) == [nil])
        #expect(!stats.library.playlists.contains { $0.id == everything.playlistID })
    }

    // MARK: Helpers

    /// The waiting episodes in Up Next, in order.
    private func queued() throws -> [Episode] {
        let store = UpNextStore(context: context)
        return try store.state().items.compactMap { try store.episode($0) }
    }

    private func makeEverything() throws -> Playlist {
        try playlists.ensureEverything()
        return try #require(try context.fetch(FetchDescriptor<Playlist>()).first(where: \.isEverything))
    }

    private func shown(_ playlist: Playlist) throws -> [String] {
        playlist.shownEpisodes(among: try context.fetch(FetchDescriptor<Playlist>())).map(\.title)
    }

    private func playlist(key: String) throws -> Playlist {
        try #require(try context.fetch(FetchDescriptor<Playlist>()).first { $0.systemKey == key })
    }

    /// A podcast "<name>" with episodes "<name>0", "<name>1", … in no playlist.
    private func insertPodcast(_ name: String, episodes count: Int) -> (Podcast, [Episode]) {
        let podcast = Podcast(feedURL: URL(string: "https://example.invalid/\(name).xml")!, title: name, subscribedAt: Self.now)
        context.insert(podcast)
        let episodes = (0..<count).map { index in
            let episode = Episode(
                guid: "\(name)\(index)", title: "\(name)\(index)", publishedAt: Self.now,
                audioURL: URL(string: "https://cdn.invalid/\(name)\(index).mp3")!)
            episode.duration = 3_600
            episode.podcast = podcast
            context.insert(episode)
            return episode
        }
        return (podcast, episodes)
    }
}

/// Moves on by a second every time it is read.
private final class StepClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(start: Date) { date = start }

    func next() -> Date {
        lock.withLock {
            date += 1
            return date
        }
    }
}
