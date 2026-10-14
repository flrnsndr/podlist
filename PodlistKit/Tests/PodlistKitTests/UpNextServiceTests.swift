import Foundation
import SwiftData
import Testing
@testable import PodlistKit

/// Up Next with SwiftData and the real player (concept §4.4 on service level).
/// Episode URLs never load; `PlayerController.currentItemDidEnd()` stands in for the end.
@MainActor
struct UpNextServiceTests {
    private let container: ModelContainer
    private let library: LibraryService
    private let playlists: PlaylistService
    private let player: PlayerController
    private let upNext: UpNextService
    private var context: ModelContext { container.mainContext }
    private nonisolated static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)

    init() throws {
        container = try PodlistStore.makeContainer(inMemory: true)
        library = LibraryService(container: container, now: { UpNextServiceTests.now })
        playlists = PlaylistService(context: container.mainContext, now: { UpNextServiceTests.now })
        player = PlayerController(library: library)
        let clock = TestClock(start: Self.now)
        upNext = UpNextService(context: container.mainContext, library: library, player: player, now: { clock.next() })
    }

    // MARK: Concept §4.4

    @Test func playingAPlaylistStoresUpNextAndItsCursor() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        upNext.playNow(a)
        #expect(player.episode == e[0])
        #expect(player.wantsToPlay)
        #expect(try render() == "▶ A0 (A) · [A]")
        #expect(a.resumeEpisode == e[0])
        #expect(try context.fetchCount(FetchDescriptor<UpNextSnapshot>()) == 0, "nothing to undo on an empty Up Next")
        #expect(upNext.undoableChange == nil)
    }

    @Test func anEndedEpisodeIsPlayedLeavesItsPlaylistAndTheNextOnePlays() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        upNext.playNow(a)
        player.currentItemDidEnd()
        #expect(player.episode == e[1])
        #expect(player.wantsToPlay)
        #expect(e[0].isPlayed && e[0].playbackPosition == 0)
        #expect(a.sortedEntries.compactMap(\.episode) == [e[1], e[2]])
        #expect(a.resumeEpisode == e[1])
        #expect(try render() == "▶ A1 (A) · [A]")
    }

    @Test func theLastEpisodeEndingEmptiesThePlayer() throws {
        let (a, _) = try insertPlaylist("A", episodes: 1)
        upNext.playNow(a)
        player.currentItemDidEnd()
        #expect(player.episode == nil)
        #expect(try render() == "–")
        #expect(upNext.isEmpty())
    }

    @Test func replacingIsRecordedAndCanBeUndone() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        let (b, f) = try insertPlaylist("B", episodes: 2)
        upNext.playNow(a)
        seek(to: 750)
        upNext.playNow(b)
        #expect(player.episode == f[0])
        #expect(try render() == "▶ B0 (B) · [B]")
        #expect(e[0].playbackPosition == 750, "replacing never loses a position")
        let change = try #require(upNext.undoableChange)
        #expect(change.playlist == b.playlistID)
        #expect(change.snapshot.reason == .replaced)

        upNext.restore(change.snapshot)
        #expect(player.episode == e[0])
        #expect(player.currentTime == 750)
        #expect(try render() == "▶ A0 (A) · [A]")
        #expect(try context.fetchCount(FetchDescriptor<UpNextSnapshot>()) == 2, "restoring is recorded too")
        #expect(upNext.undoableChange == nil)
    }

    @Test func aReplacedPlaylistStartsAgainWhereItWas() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        let (b, _) = try insertPlaylist("B", episodes: 2)
        upNext.playNow(a)
        player.currentItemDidEnd()
        upNext.playNow(b)
        upNext.playNow(a)
        #expect(player.episode == e[1])
    }

    @Test func clearingKeepsTheRunningEpisodeAndCanBeUndone() throws {
        let (a, e) = try insertPlaylist("A", episodes: 2)
        let (_, x) = try insertPlaylist("X", episodes: 1)
        upNext.playNow(a)
        upNext.playLast(x[0])
        upNext.clear()
        #expect(player.episode == e[0])
        #expect(try render() == "▶ A0 (A)")
        let change = try #require(upNext.undoableChange)
        #expect(change.playlist == nil)
        upNext.restore(change.snapshot)
        #expect(try render() == "▶ A0 (A) · [A] · X0")
    }

    @Test func playNextOnAnEmptyUpNextCuesTheEpisode() throws {
        let (_, x) = try insertPlaylist("X", episodes: 1)
        upNext.playNext(x[0])
        #expect(player.episode == x[0])
        #expect(!player.wantsToPlay)
        #expect(try render() == "▶ X0")
    }

    @Test func skipPlaysTheNextAndQueuesTheSkippedOne() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        upNext.playNow(a)
        upNext.skip()
        #expect(player.episode == e[1])
        #expect(try render() == "▶ A1 (A) · A0 · [A]")
        #expect(a.sortedEntries.count == 3, "skipping never changes the playlist")
    }

    @Test func removingTheRunningEpisodePlaysTheNextWithoutQueueingItAgain() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        upNext.playNow(a)
        seek(to: 200)
        upNext.removeNowPlaying()
        #expect(player.episode == e[1])
        #expect(player.wantsToPlay)
        #expect(try render() == "▶ A1 (A) · [A]")
        #expect(!e[0].isPlayed && e[0].playbackPosition == 200, "removing is not playing to the end")
        #expect(a.sortedEntries.count == 3, "Up Next never changes the playlist")
    }

    @Test func removingTheOnlyRunningEpisodeEmptiesThePlayer() throws {
        let (_, x) = try insertPlaylist("X", episodes: 1)
        upNext.play(x[0])
        upNext.removeNowPlaying()
        #expect(player.episode == nil)
        #expect(upNext.isEmpty())
    }

    @Test func playInTheRunningPlaylistJumps() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        upNext.playNow(a)
        upNext.play(e[2], in: a)
        #expect(player.episode == e[2])
        #expect(a.resumeEpisode == e[2])
        #expect(try render() == "▶ A2 (A) · [A]")
    }

    @Test func playingASingleEpisodeKeepsUpNext() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        let (_, z) = try insertPlaylist("Z", episodes: 1)
        upNext.playNow(a)
        seek(to: 310)
        upNext.play(z[0])
        #expect(try render() == "▶ Z0 · [A]")
        player.currentItemDidEnd()
        #expect(player.episode == e[0])
        #expect(player.currentTime == 310)
    }

    @Test func upNextComesBackPausedAfterARestart() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        upNext.playNow(a)
        seek(to: 120)
        let restarted = PlayerController(library: library)
        let service = UpNextService(context: context, library: library, player: restarted)
        service.restoreSession()
        #expect(restarted.episode == e[0])
        #expect(restarted.currentTime == 120)
        #expect(!restarted.wantsToPlay)
        #expect(service.isRunning(a))
        #expect(service.upcomingEpisodes(of: a) == [e[1], e[2]])
    }

    @Test func swipingAwayAndReordering() throws {
        let (a, _) = try insertPlaylist("A", episodes: 2)
        let (b, _) = try insertPlaylist("B", episodes: 2)
        let (_, x) = try insertPlaylist("X", episodes: 2)
        upNext.playNow(a)
        upNext.append(b)
        upNext.playLast(x[0])
        upNext.playNext(x[1])
        #expect(try render() == "▶ A0 (A) · X1 · [A] · [B] · X0")
        upNext.moveItems(fromOffsets: [3], toOffset: 0)
        #expect(try render() == "▶ A0 (A) · X0 · X1 · [A] · [B]")
        let block = try #require(try queueItems().first { $0.playlist == b })
        upNext.remove(block)
        #expect(try render() == "▶ A0 (A) · X0 · X1 · [A]")
        #expect(b.resumeEpisode == nil, "B was never played; Up Next only forgot its block")
    }

    @Test func theHistoryKeepsTheLast20States() throws {
        let (a, _) = try insertPlaylist("A", episodes: 1)
        let (b, _) = try insertPlaylist("B", episodes: 1)
        for index in 0..<25 { upNext.playNow(index.isMultiple(of: 2) ? a : b) }
        #expect(try context.fetchCount(FetchDescriptor<UpNextSnapshot>()) == UpNextHistory.limit)
        let newest = try UpNextStore(context: context).history().snapshots.first
        #expect(newest?.state.nowPlaying?.playlist == b.playlistID, "the newest snapshot is the state B replaced last")
    }

    @Test func playlistFromHereStartsAtTheEpisode() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        upNext.playNow(a, from: e[1])
        #expect(player.episode == e[1])
        #expect(a.resumeEpisode == e[1])
        #expect(try render() == "▶ A1 (A) · [A]")
    }

    @Test func aWaitingBlockOnTheEndedEpisodeMovesOnInsteadOfReplayingIt() throws {
        let (a, e) = try insertPlaylist("A", episodes: 2)
        let (b, f) = try insertPlaylist("B", episodes: 2)
        try playlists.add(e[0], to: b)
        try playlists.moveEntries(of: b, fromOffsets: [2], toOffset: 0)
        #expect(b.sortedEntries.compactMap(\.episode) == [e[0], f[0], f[1]])
        upNext.playNow(a)
        upNext.append(b, from: e[0])
        player.currentItemDidEnd()
        #expect(b.sortedEntries.compactMap(\.episode) == [f[0], f[1]], "played in A, so it left B too")
        #expect(b.resumeEpisode == f[0], "B's cursor moved on before the removal")
        player.currentItemDidEnd()
        #expect(player.episode == f[0])
    }

    @Test func restoringAClearedQueueLeavesAPausedEpisodePaused() throws {
        let (a, e) = try insertPlaylist("A", episodes: 2)
        let (_, x) = try insertPlaylist("X", episodes: 1)
        upNext.playNow(a)
        seek(to: 3_590)  // near the end: played
        player.pause()
        upNext.playLast(x[0])
        upNext.clear()
        upNext.restore(try #require(upNext.undoableChange).snapshot)
        #expect(player.episode == e[0])
        #expect(!player.wantsToPlay, "undo restores the queue, it does not start playback")
        #expect(e[0].isPlayed, "nothing was started by hand (N9)")
        #expect(player.currentTime == 3_590)
    }

    @Test func aCuedEpisodeStartsAtItsPosition() throws {
        let (_, x) = try insertPlaylist("X", episodes: 1)
        x[0].playbackPosition = 1_000
        upNext.playLast(x[0])
        #expect(player.currentTime == 1_000)
        #expect(!player.wantsToPlay)
        player.resume()
        #expect(player.wantsToPlay)
        #expect(player.currentTime == 1_000)
    }

    @Test func aCuedPlayedEpisodeStartsOverAndCountsAsStartedByHand() throws {
        // Heard almost to the end: played, the position stayed (A8).
        let (_, x) = try insertPlaylist("X", episodes: 1)
        x[0].playedAt = Self.now
        x[0].playbackPosition = 3_580
        upNext.playLast(x[0])
        #expect(player.currentTime == 0, "a played episode starts over (N23)")
        player.resume()
        #expect(!x[0].isPlayed, "N9")
        #expect(player.currentTime == 0)
    }

    @Test func upNextNeverChangesPlaylistContent() throws {
        let (a, _) = try insertPlaylist("A", episodes: 3)
        let (b, _) = try insertPlaylist("B", episodes: 2)
        let (_, x) = try insertPlaylist("X", episodes: 2)
        let contents = { [a, b].map { $0.sortedEntries.compactMap(\.episode) } }
        let before = contents()
        upNext.playNow(a)
        upNext.append(b)
        upNext.playNext(x[0])
        upNext.playLast(x[1])
        upNext.moveItems(fromOffsets: [0], toOffset: 3)
        upNext.skip()
        upNext.clear()
        let cleared = try #require(upNext.undoableChange)
        upNext.restore(cleared.snapshot)
        upNext.remove(try #require(try queueItems().first { $0.playlist == b }))
        upNext.playNow(b)
        #expect(contents() == before)
    }

    // MARK: Playlists change while Up Next runs

    @Test func removingTheRunningEpisodeByHandLetsItPlayToItsEnd() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        upNext.playNow(a)
        try playlists.remove(e[0], from: a)
        #expect(player.episode == e[0])
        #expect(try render() == "▶ A0 · [A]")
        #expect(a.resumeEpisode == e[1])
        player.currentItemDidEnd()
        #expect(player.episode == e[1])
    }

    @Test func deletingTheRunningPlaylistLetsTheEpisodePlayOn() throws {
        let (a, e) = try insertPlaylist("A", episodes: 2)
        let (_, x) = try insertPlaylist("X", episodes: 1)
        upNext.playNow(a)
        upNext.playLast(x[0])
        try playlists.delete(a)
        #expect(player.episode == e[0])
        #expect(try render() == "▶ A0 · X0")
        player.currentItemDidEnd()
        #expect(player.episode == x[0])
    }

    @Test func undoingAfterThePlaylistWasDeletedPlaysTheEpisodeAlone() throws {
        let (a, e) = try insertPlaylist("A", episodes: 2)
        let (b, _) = try insertPlaylist("B", episodes: 1)
        upNext.playNow(a)
        upNext.playNow(b)
        let change = try #require(upNext.undoableChange)
        try playlists.delete(a)
        upNext.restore(change.snapshot)
        #expect(player.episode == e[0])
        #expect(try render() == "▶ A0")
    }

    @Test func aNewEpisodeAtTheBottomPlaysAfterTheOthers() throws {
        let (a, e) = try insertPlaylist("A", episodes: 2)
        upNext.playNow(a)
        let (_, n) = try insertPlaylist("N", episodes: 1)
        try playlists.add(n[0], to: a)
        #expect(upNext.upcomingEpisodes(of: a) == [e[1], n[0]], "the block is live")
    }

    // MARK: Keep playlists use the episode's position (N12 withdrawn)

    @Test func keepPlaylistUsesTheEpisodesPosition() throws {
        let (k, e) = try insertPlaylist("K", episodes: 2, policy: .keep)
        let (b, _) = try insertPlaylist("B", episodes: 1)
        e[0].playbackPosition = 600
        upNext.playNow(k)
        #expect(player.currentTime == 600)
        seek(to: 900)
        #expect(e[0].playbackPosition == 900)
        upNext.playNow(b)
        upNext.play(e[0])
        #expect(player.currentTime == 900, "one position, wherever the episode plays")
    }

    @Test func keepPlaylistPlaysAPlayedEpisodeFromTheStart() throws {
        let (k, e) = try insertPlaylist("K", episodes: 2, policy: .keep)
        e[0].playedAt = Self.now
        e[0].playbackPosition = 0
        upNext.playNow(k)
        #expect(player.episode == e[0])
        #expect(player.currentTime == 0, "N1")
        #expect(!e[0].isPlayed, "starting it counts as unplayed again, as everywhere (N9)")
    }

    @Test func anEpisodeEndingInAKeepPlaylistIsPlayedEverywhere() throws {
        let (k, e) = try insertPlaylist("K", episodes: 2, policy: .keep)
        let (r, _) = try insertPlaylist("R", episodes: 0)
        try playlists.add(e[0], to: r)
        e[0].playbackPosition = 300
        upNext.playNow(k)
        seek(to: 1_000)
        player.currentItemDidEnd()
        #expect(player.episode == e[1])
        #expect(e[0].isPlayed)
        #expect(e[0].playbackPosition == 0)
        #expect(k.sortedEntries.count == 2, "a keep playlist keeps it")
        #expect(r.sortedEntries.isEmpty, "it left the remove playlist")
    }

    @Test func aKeepBlockComesBackAtThePositionAfterARestart() throws {
        let (k, e) = try insertPlaylist("K", episodes: 2, policy: .keep)
        e[0].playbackPosition = 100
        upNext.playNow(k)
        seek(to: 900)
        let restarted = PlayerController(library: library)
        UpNextService(context: context, library: library, player: restarted).restoreSession()
        #expect(restarted.episode == e[0])
        #expect(restarted.currentTime == 900)
    }

    @Test func undoAfterDetachingLeavesAPausedEpisodePaused() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        let (_, x) = try insertPlaylist("X", episodes: 1)
        upNext.playNow(a)
        seek(to: 600)
        upNext.append(a, from: e[2])
        player.pause()
        upNext.playLast(x[0])
        upNext.clear()
        upNext.restore(try #require(upNext.undoableChange).snapshot)
        #expect(player.episode == e[0])
        #expect(!player.wantsToPlay)
        #expect(player.currentTime == 600)
    }

    @Test func nearTheEndInAKeepPlaylistMarksTheEpisodePlayed() throws {
        let (k, e) = try insertPlaylist("K", episodes: 2, policy: .keep)
        upNext.playNow(k)
        seek(to: 3_590)
        #expect(e[0].isPlayed)
        #expect(e[0].playbackPosition == 3_590)
    }

    // MARK: "Nach der aktuellen Folge" (scenario 4c)

    @Test func playAfterCurrentKeepsTheRunningEpisodeAndWritesNoHistory() throws {
        let (a, _) = try insertPlaylist("A", episodes: 2)
        let (b, _) = try insertPlaylist("B", episodes: 2)
        upNext.playNow(a)
        upNext.playAfterCurrent(b)
        #expect(try render() == "▶ A0 (A) · [B] · [A]")
        #expect(upNext.undoableChange == nil)
        #expect(try context.fetchCount(FetchDescriptor<UpNextSnapshot>()) == 0)
        #expect(player.episode?.title == "A0")
        player.currentItemDidEnd()
        #expect(try render() == "▶ B0 (B) · [B] · [A]")
        #expect(a.resumeEpisode?.title == "A1")
    }

    @Test func playAfterCurrentOnAnEmptyUpNextStartsThePlaylist() throws {
        let (b, _) = try insertPlaylist("B", episodes: 2)
        upNext.playAfterCurrent(b, from: nil)
        #expect(try render() == "▶ B0 (B) · [B]")
        #expect(player.episode?.title == "B0")
    }

    // MARK: Playlists follow the queue (N94, N96, A79)

    @Test func playNextInTheRunningPlaylistMovesTheEntryBelowTheRunningEpisode() throws {
        let (a, e) = try insertPlaylist("A", episodes: 4)
        upNext.playNow(a)
        upNext.playNext(e[3])
        #expect(a.sortedEntries.compactMap(\.episode) == [e[0], e[3], e[1], e[2]])
        #expect(try render() == "▶ A0 (A) · [A]")
        #expect(player.episode == e[0])
        player.currentItemDidEnd()
        #expect(player.episode == e[3])
        #expect(try render() == "▶ A3 (A) · [A]")
    }

    /// N96: a sorted playlist becomes manual, starting from what it showed.
    @Test func playNextSwitchesASortedPlaylistToManual() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        try playlists.setSort(.title, ascending: false, of: a)  // A2, A1, A0
        upNext.playNow(a)
        upNext.playNext(e[0])
        #expect(a.sort == .manual)
        #expect(a.sortedEntries.compactMap(\.episode) == [e[2], e[0], e[1]])
        #expect(try render() == "▶ A2 (A) · [A]")
    }

    /// Florian's example: B1 dragged past B0 and C0 moves behind B0 in B; C stays as it is,
    /// also its sort.
    @Test func draggingInUpNextMovesTheEpisodeInItsPlaylistsOnly() throws {
        let (_, x) = try insertPlaylist("X", episodes: 1)
        let (b, e) = try insertPlaylist("B", episodes: 3)
        let (c, f) = try insertPlaylist("C", episodes: 2)
        try playlists.setSort(.title, ascending: true, of: c)
        upNext.play(x[0])
        upNext.playLast(e[1])
        upNext.playLast(e[0])
        upNext.playLast(f[0])
        #expect(b.sortedEntries.compactMap(\.episode) == e, "Am Ende changes no playlist")
        upNext.moveItems(fromOffsets: [0], toOffset: 3)
        #expect(try render() == "▶ X0 · B0 · C0 · B1")
        #expect(b.sortedEntries.compactMap(\.episode) == e, "B1 already follows B0")

        upNext.moveItems(fromOffsets: [2], toOffset: 0)
        #expect(try render() == "▶ X0 · B1 · B0 · C0")
        #expect(b.sortedEntries.compactMap(\.episode) == [e[1], e[0], e[2]])
        #expect(c.sort == .title, "C did not change")
    }

    /// "Jetzt" on an episode whose playlist is not in Up Next: it moves right before the
    /// playlist's Wiedergabestand.
    @Test func playingAnEpisodeMovesItBeforeTheResumePointOfItsPlaylist() throws {
        let (a, e) = try insertPlaylist("A", episodes: 4)
        let (b, _) = try insertPlaylist("B", episodes: 1)
        upNext.playNow(a, from: e[1])
        upNext.playNow(b)
        #expect(a.resumeEpisode == e[1])
        upNext.play(e[3])
        #expect(a.sortedEntries.compactMap(\.episode) == [e[0], e[3], e[1], e[2]])
    }

    /// "Alles" has no order of its own; its block's episodes are neighbours like any others.
    @Test func everythingIsNoTargetButItsEpisodesAreNeighbours() throws {
        try playlists.ensureEverything()
        let everything = try #require(try context.fetch(FetchDescriptor<Playlist>()).first(where: \.isEverything))
        let (a, e) = try insertPlaylist("A", episodes: 3)
        for (index, entry) in a.sortedEntries.enumerated() { entry.addedAt = Self.now.addingTimeInterval(Double(index)) }
        // Alles: A2, A1, A0 (newest added first, N97)
        upNext.playNow(everything)
        #expect(player.episode == e[2])
        upNext.playNext(e[0])
        #expect(a.sortedEntries.compactMap(\.episode) == [e[1], e[2], e[0]], "behind the running A2")
        #expect((everything.entries ?? []).isEmpty)
        #expect(upNext.upcomingEpisodes(of: everything) == [e[1], e[0]], "Alles keeps its own order")
    }

    // MARK: Helpers

    /// A playlist with its own podcast "<name>" and episodes "<name>0", "<name>1", … (manual sort).
    private func insertPlaylist(_ name: String, episodes count: Int, policy: PlayedPolicy = .remove) throws -> (Playlist, [Episode]) {
        let playlist = try playlists.createPlaylist(name: name, colorKey: "blue", symbolName: "star")
        try playlists.setPlayedPolicy(policy, of: playlist)
        let podcast = Podcast(feedURL: URL(string: "https://example.invalid/\(name).xml")!, title: name, subscribedAt: Self.now)
        context.insert(podcast)
        var episodes: [Episode] = []
        for index in 0..<count {
            let episode = Episode(
                guid: "\(name)\(index)", title: "\(name)\(index)", publishedAt: Self.now,
                audioURL: URL(string: "https://cdn.invalid/\(name)\(index).mp3")!)
            episode.duration = 3_600
            episode.podcast = podcast
            context.insert(episode)
            try playlists.add(episode, to: playlist)
            episodes.append(episode)
        }
        return (playlist, episodes)
    }

    /// The loaded episode is ready (URLs never load here), then the user seeks.
    private func seek(to position: TimeInterval) {
        player.currentItemBecameReady()
        player.seek(to: position)
    }


    private func queueItems() throws -> [QueueItem] {
        try context.fetch(FetchDescriptor<QueueItem>(sortBy: [SortDescriptor(\.position)]))
    }

    /// "▶ A0 (A) · X1 · [A]": the running episode with its block's playlist, then the items.
    private func render() throws -> String {
        var parts: [String] = []
        let items = try queueItems()
        if let now = items.first(where: \.isNowPlaying), let episode = now.episode {
            parts.append("▶ " + episode.title + (now.playlist.map { " (\($0.customName ?? ""))" } ?? ""))
        }
        for item in items where !item.isNowPlaying {
            if let episode = item.episode { parts.append(episode.title) }
            if let playlist = item.playlist { parts.append("[\(playlist.customName ?? "")]") }
        }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }
}

/// A clock that moves on by a second every time it is read, so history entries have
/// distinct, increasing dates.
private final class TestClock: @unchecked Sendable {
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
