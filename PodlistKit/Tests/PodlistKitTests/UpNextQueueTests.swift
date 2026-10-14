import Foundation
import Testing
@testable import PodlistKit

// Slice 3: the queue operations the Up Next screen needs on top of concept §4.4
// (swiping away, reordering, a block's upcoming episodes, deleting a playlist,
// adding to an empty Up Next). Notation and `QueueWorld` as in QueueResolverTests.

@Suite("QueueResolver — Up Next editing")
struct UpNextEditingTests {
    // MARK: Adding single episodes

    @Test func playNextWhilePlayingDoesNotInterrupt() {
        var w = QueueWorld()
        w.playNow("A")
        w.playNext("X")
        #expect(w.render() == "▶ A1 · X · [A]")
        #expect(w.lastCommand == nil)
    }

    @Test func playNextOnAnEmptyUpNextCuesTheEpisode() {
        // ASSUMPTION (A22): the episode is loaded paused, so the mini player shows it.
        var w = QueueWorld()
        w.playNext("X")
        #expect(w.render() == "▶ X")
        #expect(w.lastCommand == .cue(QueueWorld.episode("X")))
    }

    @Test func playLastOnAnEmptyUpNextCuesTheEpisode() {
        var w = QueueWorld()
        w.playLast("Y")
        #expect(w.render() == "▶ Y")
        #expect(w.lastCommand == .cue(QueueWorld.episode("Y")))
    }

    @Test func playNextWithTheRunningEpisodeChangesNothing() {
        var w = QueueWorld()
        w.play("Z")
        w.playNext("Z")
        #expect(w.render() == "▶ Z")
        #expect(w.lastCommand == nil)
    }

    // MARK: Swiping away

    @Test func removingASingleEpisode() {
        var w = QueueWorld()
        w.playNow("A")
        w.playNext("X")
        w.remove("X")
        #expect(w.render() == "▶ A1 · [A]")
        #expect(w.lastCommand == nil)
    }

    @Test func removingAWaitingBlockKeepsItsCursor() {
        var w = QueueWorld()
        w.playNow("A")
        w.append("B", from: "B2")
        w.remove("[B]")
        #expect(w.render() == "▶ A1 · [A]")
        #expect(w.resume("B") == "B2", "Up Next only forgets the block; B keeps its place")
        #expect(w.contents("B") == ["B1", "B2", "B3"])
    }

    @Test func removingTheRunningBlockLetsTheEpisodePlayToItsEnd() {
        var w = QueueWorld()
        w.playNow("A")
        w.playLast("Y")
        w.remove("[A]")
        #expect(w.render() == "▶ A1 · Y")
        #expect(w.lastCommand == nil, "the running episode is not interrupted")
        w.end()
        #expect(w.render() == "▶ Y")
        #expect(w.resume("A") == "A2", "A remembers that A1 was heard")
    }

    @Test func runningEpisodeOfARemovedBlockComesBackWhenInterrupted() {
        var w = QueueWorld()
        w.playNow("A")
        w.remove("[A]")
        w.play("Z")
        #expect(w.render() == "▶ Z · A1")
    }

    // MARK: Reordering

    @Test(arguments: [
        (IndexSet([2]), 0, "▶ A1 · Y · X · [A]"),
        (IndexSet([0]), 3, "▶ A1 · [A] · Y · X"),
        (IndexSet([1]), 0, "▶ A1 · [A] · X · Y"),
        (IndexSet([0, 1]), 3, "▶ A1 · Y · X · [A]"),
    ])
    func movingItems(offsets: IndexSet, destination: Int, expected: String) {
        var w = QueueWorld()
        w.playNow("A")
        w.playNext("X")
        w.playLast("Y")
        #expect(w.render() == "▶ A1 · X · [A] · Y")
        w.moveItems(from: offsets, to: destination)
        #expect(w.render() == expected)
        #expect(w.lastCommand == nil, "reordering never interrupts playback")
    }

    @Test func movingABlockBehindASingleEpisodeKeepsTheRunningEpisode() {
        var w = QueueWorld()
        w.playNow("A")
        w.playLast("Y")
        w.moveItems(from: [0], to: 2)
        #expect(w.render() == "▶ A1 · Y · [A]")
        w.end()
        #expect(w.render() == "▶ Y · [A]")
        #expect(w.resume("A") == "A2")
        w.end()
        #expect(w.render() == "▶ A2 · [A]")
    }

    // MARK: Deleting a playlist

    @Test func deletingTheRunningPlaylistLetsTheEpisodePlayOn() {
        var w = QueueWorld()
        w.playNow("A")
        w.playLast("Y")
        w.deletePlaylist("A")
        #expect(w.render() == "▶ A1 · Y")
        w.end()
        #expect(w.render() == "▶ Y")
    }

    @Test func deletingAWaitingPlaylistDropsItsBlock() {
        var w = QueueWorld()
        w.playNow("A")
        w.append("B")
        w.deletePlaylist("B")
        #expect(w.render() == "▶ A1 · [A]")
    }

    @Test func undoAfterThePlaylistWasDeletedPlaysTheEpisodeAlone() {
        var w = QueueWorld()
        w.playNow("A")
        w.playNow("B")
        w.deletePlaylist("A")
        w.undo()
        #expect(w.render() == "▶ A1 · [A]")
        w.end()
        #expect(w.render() == "–", "the unknown block is dropped when it comes to the front")
    }
}

@Suite("QueueResolver — upcoming episodes of a block")
struct UpcomingEpisodesTests {
    @Test func runningRemoveBlockShowsTheEpisodesAfterTheRunningOne() {
        var w = QueueWorld()
        w.playNow("A")
        #expect(w.upcoming("A") == ["A2", "A3", "A4"])
    }

    @Test func removeBlockWrapsAroundAndLeavesOutTheRunningEpisode() {
        var w = QueueWorld()
        w.playNow("A", from: "A3")
        #expect(w.upcoming("A") == ["A4", "A1", "A2"])
    }

    @Test func waitingBlockStartsAtItsCursor() {
        var w = QueueWorld()
        w.playNow("A")
        w.append("B", from: "B2")
        #expect(w.upcoming("B") == ["B2", "B3", "B1"])
    }

    @Test func runningBlockBehindASingleEpisodeStartsAtItsCursor() {
        var w = QueueWorld()
        w.playNow("A")
        w.playNext("X")
        w.end()  // A1
        #expect(w.render() == "▶ X · [A]")
        #expect(w.upcoming("A") == ["A2", "A3", "A4"])
    }

    @Test func keepBlockEndsAtItsLastEpisode() {
        var w = QueueWorld()
        w.playNow("K", from: "K2")
        #expect(w.upcoming("K") == ["K3"])
        w.playNow("A")
        w.append("K")
        #expect(w.upcoming("K") == ["K2", "K3"], "K's cursor is still K2")
    }

    @Test func keepBlockIncludesPlayedEpisodes() {
        var w = QueueWorld()
        w.playNow("A")
        w.append("K")
        #expect(w.upcoming("K") == ["K1", "K2", "K3"])
    }

    @Test func removeBlockSkipsEpisodesPlayedElsewhere() {
        var w = QueueWorld()
        w.markPlayedWithoutPolicy("B2")
        w.playNow("A")
        w.append("B")
        #expect(w.upcoming("B") == ["B1", "B3"])
    }

    @Test func playlistWithoutPlayableEpisodesShowsNothing() {
        var w = QueueWorld(startPlaylists: [("B", ["B1"])])
        w.markPlayedWithoutPolicy("B1")
        #expect(w.upcoming("B") == [])
        #expect(w.upcoming("unknown") == [])
    }

    @Test func upcomingMatchesWhatActuallyPlays() {
        var w = QueueWorld()
        w.playNow("A", from: "A2")
        let upcoming = w.upcoming("A")
        #expect(w.playthrough() == upcoming)
    }
}
