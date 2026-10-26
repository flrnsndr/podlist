import Foundation
import SwiftData
import Testing
@testable import PodlistKit

/// Up Next with SwiftData and the real player (concept §4.4 v0.7 on service level, ADR 0008).
/// Episode URLs never load; `PlayerController.currentItemDidEnd()` stands in for the end.
/// The rules themselves are tested in `UpNextScenarioTests`; here: persistence, the player,
/// the played policy, resume points (N107) and the migration of stored blocks (A90).
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

    @Test func playingAPlaylistTakesItOverAndStoresUpNext() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        upNext.playNow(a)
        #expect(player.episode == e[0])
        #expect(player.wantsToPlay)
        #expect(try render() == "▶ A0 · A1 · A2")
        #expect(upNext.isRunning(a))
        #expect(a.resumeEpisode == nil, "while queued the resume point is derived, not stored (N107)")
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
        #expect(try render() == "▶ A1 · A2")
    }

    @Test func theLastEpisodeEndingEmptiesThePlayerAndTheResumePoint() throws {
        let (a, _) = try insertPlaylist("A", episodes: 1)
        upNext.playNow(a)
        player.currentItemDidEnd()
        #expect(player.episode == nil)
        #expect(try render() == "–")
        #expect(upNext.isEmpty())
        #expect(a.resumeEpisode == nil)
    }

    @Test func replacingIsRecordedAndCanBeUndone() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        let (b, f) = try insertPlaylist("B", episodes: 2)
        upNext.playNow(a)
        seek(to: 750)
        upNext.playNow(b)
        #expect(player.episode == f[0])
        #expect(try render() == "▶ B0 · B1")
        #expect(e[0].playbackPosition == 750, "replacing never loses a position")
        #expect(a.resumeEpisode == e[0], "A remembers where it was (N107)")
        let change = try #require(upNext.undoableChange)
        #expect(change.playlist == b.playlistID)
        #expect(change.snapshot.reason == .replaced)

        upNext.restore(change.snapshot)
        #expect(player.episode == e[0])
        #expect(player.currentTime == 750)
        #expect(try render() == "▶ A0 · A1 · A2")
        #expect(b.resumeEpisode == f[0], "B remembers B0")
        #expect(try context.fetchCount(FetchDescriptor<UpNextSnapshot>()) == 2, "restoring is recorded too")
        #expect(upNext.undoableChange == nil)
    }

    @Test func aReplacedPlaylistStartsAgainWhereItWas() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        let (b, _) = try insertPlaylist("B", episodes: 2)
        upNext.playNow(a)
        player.currentItemDidEnd()
        upNext.playNow(b)
        #expect(a.resumeEpisode == e[1])
        upNext.playNow(a)
        #expect(player.episode == e[1])
        #expect(try render() == "▶ A1 · A2")
    }

    @Test func clearingKeepsTheRunningEpisodeAndCanBeUndone() throws {
        let (a, e) = try insertPlaylist("A", episodes: 2)
        let (_, x) = try insertPlaylist("X", episodes: 1)
        upNext.playNow(a)
        upNext.playLast(x[0])
        upNext.clear()
        #expect(player.episode == e[0])
        #expect(try render() == "▶ A0")
        let change = try #require(upNext.undoableChange)
        #expect(change.playlist == nil)
        upNext.restore(change.snapshot)
        #expect(try render() == "▶ A0 · A1 · X0")
    }

    @Test func playNextOnAnEmptyUpNextCuesTheEpisode() throws {
        let (_, x) = try insertPlaylist("X", episodes: 1)
        upNext.playNext(x[0])
        #expect(player.episode == x[0])
        #expect(!player.wantsToPlay)
        #expect(try render() == "▶ X0")
    }

    @Test func playNextAndPlayLastMoveAQueuedEpisode() throws {
        let (a, e) = try insertPlaylist("A", episodes: 4)
        upNext.playNow(a)
        upNext.playNext(e[2])
        #expect(try render() == "▶ A0 · A2 · A1 · A3")
        upNext.playLast(e[2])
        #expect(try render() == "▶ A0 · A1 · A3 · A2")
        #expect(a.sortedEntries.compactMap(\.episode) == e, "the queue never changes a playlist (N104)")
    }

    // MARK: ⏭ (scenario 9, N101)

    @Test func skipCountsAsHeardAndPlaysTheNext() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        upNext.playNow(a)
        seek(to: 200)
        #expect(upNext.episodeAfterSkip() == e[1])
        upNext.skip()
        #expect(player.episode == e[1])
        #expect(player.wantsToPlay)
        #expect(try render() == "▶ A1 · A2", "the skipped episode does not come back")
        #expect(e[0].isPlayed && e[0].playbackPosition == 0)
        #expect(a.sortedEntries.compactMap(\.episode) == [e[1], e[2]], "the played policy removed it")
        #expect(try context.fetchCount(FetchDescriptor<UpNextSnapshot>()) == 0, "⏭ replaces nothing")
        #expect(upNext.undoableChange?.kind == .skipped(e[0].episodeID))
    }

    @Test func skipWhilePausedCuesTheNext() throws {
        let (a, e) = try insertPlaylist("A", episodes: 2)
        upNext.playNow(a)
        seek(to: 200)
        player.pause()
        upNext.skip()
        #expect(player.episode == e[1])
        #expect(!player.wantsToPlay)
        #expect(e[0].isPlayed)
    }

    /// ⏭ is disabled without a next episode; called anyway, it changes nothing.
    @Test func skipWithoutANextEpisodeDoesNothing() throws {
        let (a, e) = try insertPlaylist("A", episodes: 1)
        upNext.playNow(a)
        seek(to: 200)
        #expect(upNext.episodeAfterSkip() == nil)
        upNext.skip()
        #expect(player.episode == e[0])
        #expect(!e[0].isPlayed)
        #expect(e[0].playbackPosition == 200)
        #expect(upNext.undoableChange == nil)
    }

    /// A81: everything comes back, the episode at its place in the playlist and in the player.
    @Test func undoingASkipRestoresEverything() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        let (_, x) = try insertPlaylist("X", episodes: 1)
        upNext.playNow(a, from: e[1])
        upNext.playLast(x[0])
        seek(to: 750)
        upNext.skip()
        #expect(try render() == "▶ A2 · A0 · X0")
        let change = try #require(upNext.undoableChange)

        upNext.undo(change)
        #expect(player.episode == e[1])
        #expect(player.wantsToPlay, "it played before")
        #expect(player.currentTime == 750)
        #expect(!e[1].isPlayed)
        #expect(e[1].playbackPosition == 750)
        #expect(a.sortedEntries.compactMap(\.episode) == e, "back at its former place")
        #expect(try render() == "▶ A1 · A2 · A0 · X0")
        #expect(upNext.undoableChange == nil)
        let history = try context.fetch(FetchDescriptor<UpNextSnapshot>()).map { try $0.value() }
        #expect(history.map(\.reason) == [.restored], "undo sets Up Next back, so it is recorded")
        #expect(upNext.episodeAfterSkip() == e[2])
    }

    @Test func undoingASkipWhilePausedLeavesItPaused() throws {
        let (a, e) = try insertPlaylist("A", episodes: 2)
        upNext.playNow(a)
        seek(to: 300)
        player.pause()
        upNext.skip()
        upNext.undo(try #require(upNext.undoableChange))
        #expect(player.episode == e[0])
        #expect(!player.wantsToPlay)
        #expect(player.currentTime == 300)
    }

    /// A keep playlist keeps the skipped episode, marked played; undo takes that back.
    @Test func skipInAKeepPlaylistKeepsTheEpisodeAndUndoUnmarksIt() throws {
        let (k, e) = try insertPlaylist("K", episodes: 3, policy: .keep)
        upNext.playNow(k)
        upNext.skip()
        #expect(e[0].isPlayed)
        #expect(k.sortedEntries.count == 3)
        upNext.undo(try #require(upNext.undoableChange))
        #expect(!e[0].isPlayed)
        #expect(try render() == "▶ K0 · K1 · K2")
    }

    /// Skipping the last queued episode of a playlist leaves no resume point (N107).
    @Test func skippingTheLastEpisodeOfAPlaylistForgetsItsResumePoint() throws {
        let (k, e) = try insertPlaylist("K", episodes: 1, policy: .keep)
        let (_, x) = try insertPlaylist("X", episodes: 1)
        upNext.playNow(k)
        upNext.playLast(x[0])
        upNext.skip()
        #expect(player.episode == x[0])
        #expect(e[0].isPlayed)
        #expect(k.resumeEpisode == nil)
    }

    /// N107: single episodes passing through Up Next leave a playlist's stored resume point
    /// alone; a takeover clears it.
    @Test func aSingleEpisodeEndingLeavesTheStoredResumePointAlone() throws {
        let (k, e) = try insertPlaylist("K", episodes: 3, policy: .keep)
        let (x, _) = try insertPlaylist("X", episodes: 1)
        k.resumeEpisode = e[1]
        upNext.playNow(x)
        upNext.playNext(e[2])
        player.currentItemDidEnd()
        #expect(player.episode == e[2])
        player.currentItemDidEnd()
        #expect(player.episode == nil)
        #expect(k.resumeEpisode == e[1], "K2 ended, K1 stays 'Weiter bei'")
        upNext.playNow(k)
        #expect(player.episode == e[1])
        #expect(k.resumeEpisode == nil, "taken over: derived from now on")
    }

    /// Only the latest change can be undone: a second ⏭ or a replacement ends the first undo.
    @Test func aNewChangeEndsTheUndoOfASkip() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        let (b, _) = try insertPlaylist("B", episodes: 1)
        upNext.playNow(a)
        upNext.skip()
        let first = try #require(upNext.undoableChange)
        upNext.skip()
        #expect(upNext.undoableChange?.kind == .skipped(e[1].episodeID))
        upNext.undo(first)
        #expect(player.episode == e[2], "a former undo does nothing")
        upNext.playNow(b)
        #expect(upNext.undoableChange?.kind == .replaced(b.playlistID))
        upNext.dismissUndo()
        #expect(upNext.undoableChange == nil)
    }

    // MARK: Editing Up Next

    @Test func removingTheRunningEpisodePlaysTheNextWithoutQueueingItAgain() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        upNext.playNow(a)
        seek(to: 200)
        upNext.removeNowPlaying()
        #expect(player.episode == e[1])
        #expect(player.wantsToPlay)
        #expect(try render() == "▶ A1 · A2")
        #expect(!e[0].isPlayed && e[0].playbackPosition == 200, "removing is not playing to the end")
        #expect(a.sortedEntries.count == 3, "Up Next never changes the playlist")
    }

    @Test func removingTheOnlyRunningEpisodeEmptiesThePlayerAndRemembersIt() throws {
        let (a, e) = try insertPlaylist("A", episodes: 1)
        upNext.playNow(a)
        upNext.removeNowPlaying()
        #expect(player.episode == nil)
        #expect(upNext.isEmpty())
        #expect(a.resumeEpisode == e[0], "swiped away unplayed: 'Weiter bei' (N107)")
    }

    @Test func playOnAQueuedEpisodeMovesItToTheFront() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        upNext.playNow(a)
        seek(to: 310)
        upNext.play(e[2])
        #expect(player.episode == e[2])
        #expect(try render() == "▶ A2 · A0 · A1", "A0 comes back in front, A2 is not left behind (N105)")
        player.currentItemDidEnd()
        #expect(player.episode == e[0])
        #expect(player.currentTime == 310)
    }

    @Test func swipingAwayAndReordering() throws {
        let (a, e) = try insertPlaylist("A", episodes: 2)
        let (b, f) = try insertPlaylist("B", episodes: 2)
        let (_, x) = try insertPlaylist("X", episodes: 2)
        upNext.playNow(a)
        upNext.append(b)
        upNext.playLast(x[0])
        upNext.playNext(x[1])
        #expect(try render() == "▶ A0 · X1 · A1 · B0 · B1 · X0")
        upNext.moveItems(fromOffsets: [4], toOffset: 0)
        #expect(try render() == "▶ A0 · X0 · X1 · A1 · B0 · B1")
        upNext.remove(f[0])
        upNext.remove(f[1])
        #expect(try render() == "▶ A0 · X0 · X1 · A1")
        #expect(b.resumeEpisode == f[1], "B left unplayed with the second swipe: it remembers B1, its frontmost then (N107)")
        upNext.move(e[1], behind: nil)
        #expect(try render() == "▶ A0 · A1 · X0 · X1", "dragged in A's live part to the top (N106)")
        upNext.move(e[1], behind: x[1])
        #expect(try render() == "▶ A0 · X0 · X1 · A1")
        #expect([a, b].map { $0.sortedEntries.compactMap(\.episode) } == [e, f], "no playlist changed")
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
    }

    @Test func theHistoryKeepsTheLast20States() throws {
        let (a, _) = try insertPlaylist("A", episodes: 1)
        let (b, f) = try insertPlaylist("B", episodes: 1)
        for index in 0..<25 { upNext.playNow(index.isMultiple(of: 2) ? a : b) }
        #expect(try context.fetchCount(FetchDescriptor<UpNextSnapshot>()) == UpNextHistory.limit)
        let newest = try UpNextStore(context: context).history().snapshots.first
        #expect(newest?.state.nowPlaying == f[0].episodeID, "the newest snapshot is the state B replaced last")
    }

    @Test func playlistFromHereStartsAtTheEpisode() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        upNext.playNow(a, from: e[1])
        #expect(player.episode == e[1])
        #expect(try render() == "▶ A1 · A2 · A0", "a 'remove' playlist goes round once")
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

    @Test func upNextNeverChangesAPlaylist() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        let (b, f) = try insertPlaylist("B", episodes: 2)
        let (_, x) = try insertPlaylist("X", episodes: 2)
        try playlists.setSort(.title, ascending: false, of: b)
        let contents = { [a, b].map { $0.sortedEntries.compactMap(\.episode) } }
        let before = contents()
        upNext.playNow(a)
        upNext.append(b)
        upNext.playNext(x[0])
        upNext.playNext(e[2])
        upNext.playLast(x[1])
        upNext.play(f[0])
        upNext.moveItems(fromOffsets: [0], toOffset: 3)
        upNext.move(e[1], behind: nil)
        upNext.clear()
        let cleared = try #require(upNext.undoableChange)
        upNext.restore(cleared.snapshot)
        upNext.remove(e[1])
        upNext.playNow(b)
        #expect(contents() == before)
        #expect(b.sort == .title, "not even its sort (N96 only for dragging in the draft)")
    }

    // MARK: Playlists change while Up Next runs (A86–A88)

    @Test func removingAQueuedEpisodeByHandLeavesUpNextAlone() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        upNext.playNow(a)
        try playlists.remove(e[1], from: a)
        #expect(try render() == "▶ A0 · A1 · A2", "A88")
        #expect(a.sortedEntries.compactMap(\.episode) == [e[0], e[2]])
        player.currentItemDidEnd()
        #expect(player.episode == e[1], "it still plays")
    }

    @Test func deletingTheRunningPlaylistLeavesUpNextAlone() throws {
        let (a, e) = try insertPlaylist("A", episodes: 2)
        let (_, x) = try insertPlaylist("X", episodes: 1)
        upNext.playNow(a)
        upNext.playLast(x[0])
        try playlists.delete(a)
        #expect(player.episode == e[0])
        #expect(try render() == "▶ A0 · A1 · X0")
        player.currentItemDidEnd()
        #expect(player.episode == e[1])
    }

    @Test func undoingAfterThePlaylistWasDeletedStillRestores() throws {
        let (a, e) = try insertPlaylist("A", episodes: 2)
        let (b, _) = try insertPlaylist("B", episodes: 1)
        upNext.playNow(a)
        upNext.playNow(b)
        let change = try #require(upNext.undoableChange)
        try playlists.delete(a)
        upNext.restore(change.snapshot)
        #expect(player.episode == e[0])
        #expect(try render() == "▶ A0 · A1")
    }

    @Test func aNewEpisodeWaitsInTheDraft() throws {
        let (a, e) = try insertPlaylist("A", episodes: 2)
        upNext.playNow(a)
        let (_, n) = try insertPlaylist("N", episodes: 1)
        try playlists.add(n[0], to: a)
        #expect(try render() == "▶ A0 · A1", "A86: the queue is not told")
        let parts = upNext.split(of: a, among: try context.fetch(Playlist.allWithEntries()))
        #expect(parts.live == [e[0], e[1]])
        #expect(parts.draft == [n[0]])
    }

    @Test func aResumePointWhoseEpisodeLeftThePlaylistReadsAsEmpty() throws {
        let (a, e) = try insertPlaylist("A", episodes: 2)
        let (b, _) = try insertPlaylist("B", episodes: 1)
        upNext.playNow(a)
        upNext.playNow(b)
        #expect(a.resumeEpisode == e[0])
        try playlists.remove(e[0], from: a)
        upNext.playNow(a)
        #expect(player.episode == e[1], "starts at the top (N107, N13 is gone)")
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

    @Test func aKeepPlaylistComesBackAtThePositionAfterARestart() throws {
        let (k, e) = try insertPlaylist("K", episodes: 2, policy: .keep)
        e[0].playbackPosition = 100
        upNext.playNow(k)
        seek(to: 900)
        let restarted = PlayerController(library: library)
        UpNextService(context: context, library: library, player: restarted).restoreSession()
        #expect(restarted.episode == e[0])
        #expect(restarted.currentTime == 900)
    }

    @Test func undoAfterReplacingLeavesAPausedEpisodePaused() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        let (_, x) = try insertPlaylist("X", episodes: 1)
        upNext.playNow(a)
        seek(to: 600)
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

    // MARK: "Nach der aktuellen Folge" and "Ans Ende" (scenarios 4a, 4c)

    @Test func playAfterCurrentKeepsTheRunningEpisodeAndWritesNoHistory() throws {
        let (_, e) = try insertPlaylist("A", episodes: 2)
        let (b, _) = try insertPlaylist("B", episodes: 2)
        upNext.playNow(try #require(e[0].playlistEntries?.first?.playlist))
        upNext.playAfterCurrent(b)
        #expect(try render() == "▶ A0 · B0 · B1 · A1")
        #expect(upNext.undoableChange == nil)
        #expect(try context.fetchCount(FetchDescriptor<UpNextSnapshot>()) == 0)
        #expect(player.episode?.title == "A0")
        player.currentItemDidEnd()
        #expect(try render() == "▶ B0 · B1 · A1")
    }

    @Test func playAfterCurrentOnAnEmptyUpNextStartsThePlaylist() throws {
        let (b, _) = try insertPlaylist("B", episodes: 2)
        upNext.playAfterCurrent(b, from: nil)
        #expect(try render() == "▶ B0 · B1")
        #expect(player.episode?.title == "B0")
    }

    @Test func appendingAPlaylistAlreadyPartlyQueuedMovesItsEpisodes() throws {
        let (a, _) = try insertPlaylist("A", episodes: 1)
        let (b, f) = try insertPlaylist("B", episodes: 3)
        upNext.playNow(a)
        upNext.playNext(f[1])
        upNext.append(b)
        #expect(try render() == "▶ A0 · B1 · B2 · B0", "taken over from its frontmost queued episode, B1 moves (N105, N107)")
    }

    // MARK: Playlists overview (N107: Läuft / Als Nächstes / Weiter bei)

    @Test func thePlaylistsOverviewTellsWhereEachPlaylistStands() throws {
        let (a, e) = try insertPlaylist("A", episodes: 2)
        let (b, f) = try insertPlaylist("B", episodes: 2)
        let (c, g) = try insertPlaylist("C", episodes: 2)
        let (d, _) = try insertPlaylist("D", episodes: 0)
        upNext.playNow(c)
        player.currentItemDidEnd()
        upNext.playNow(a)
        upNext.playNext(f[1])
        let overview = upNext.playlistsOverview(of: try context.fetch(Playlist.allWithEntries()))
        #expect(overview.next[a.playlistID] == e[0] && overview.running.contains(a.playlistID), "Läuft")
        #expect(overview.next[b.playlistID] == f[1] && overview.queued.contains(b.playlistID), "Als Nächstes")
        #expect(overview.next[c.playlistID] == g[1], "Weiter bei (replaced while queued)")
        #expect(!overview.running.contains(c.playlistID) && !overview.queued.contains(c.playlistID))
        #expect(overview.next[d.playlistID] == nil)
    }

    // MARK: Migration of a store with blocks (A90)

    @Test func storedBlocksAreTakenOverOnceAndTheHistoryIsCleared() throws {
        let (a, e) = try insertPlaylist("A", episodes: 3)
        let (b, f) = try insertPlaylist("B", episodes: 2)
        let (_, x) = try insertPlaylist("X", episodes: 1)
        a.resumeEpisode = e[1]
        b.resumeEpisode = f[1]
        context.insert(QueueItem(nowPlaying: e[1], playlist: a))
        context.insert(QueueItem(position: 0, episode: x[0]))
        context.insert(QueueItem(position: 1, playlist: b))
        let legacy = try UpNextSnapshot(UpNextSnapshotValue(createdAt: Self.now, reason: .replaced, state: UpNextState()))
        legacy.payload = Data("{\"items\":[{\"playlist\":{\"_0\":{\"uuid\":\"\(UUID().uuidString)\"}}}]}".utf8)
        context.insert(legacy)
        try context.save()

        #expect(try render() == "▶ A1 · A2 · A0 · X0 · B1 · B0", "the running block continues behind its episode, the waiting block starts at its resume point (A90)")
        #expect(try context.fetch(FetchDescriptor<QueueItem>()).allSatisfy { $0.playlist == nil }, "written back flat")
        #expect(try context.fetchCount(FetchDescriptor<UpNextSnapshot>()) == 0, "the old history is gone")
        upNext.restoreSession()
        #expect(player.episode == e[1])
        #expect(upNext.isRunning(a))
        player.resume()
        player.currentItemDidEnd()
        #expect(player.episode == e[2])
        #expect(b.resumeEpisode == nil && f[0].playlistEntries?.count == 1, "taken over: the stored resume point is cleared (N107)")
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

    /// "▶ A0 · X1 · A1": the running episode, then the waiting ones, as the store reads them.
    private func render() throws -> String {
        let state = try UpNextStore(context: context).state()
        let store = UpNextStore(context: context)
        var parts: [String] = []
        if let now = state.nowPlaying, let episode = try store.episode(now) { parts.append("▶ " + episode.title) }
        for id in state.items { if let episode = try store.episode(id) { parts.append(episode.title) } }
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
