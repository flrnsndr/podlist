import Foundation
import Testing
@testable import PodlistKit

// Concept §4.4 as tests. Every row of the scenario table is one argument of
// `scenarioTable`; the special cases below the table and the cursor rules follow.
// Notation as in the concept: "▶ A1 · X · [A]" = A1 plays, then X, then the block of
// playlist A. "–" = Up Next is empty.

// MARK: - Scenario table

struct QueueScenario: Sendable, CustomTestStringConvertible {
    let number: String
    /// Builds the "Vorher" state from an empty Up Next.
    let setup: @Sendable (inout QueueWorld) -> Void
    let before: String
    let action: @Sendable (inout QueueWorld) -> Void
    let after: String
    /// Further expectations of the row (positions, history, playlist content, follow-ups).
    var check: @Sendable (QueueWorld) -> Void = { _ in }

    var testDescription: String { "Szenario \(number)" }
}

/// ▶ A1 · X · [A]  (rows 2–4)
@Sendable private func a1XA(_ w: inout QueueWorld) {
    w.playNow("A")
    w.playNext("X")
}

/// ▶ A2 · [A] with A1 played and removed from A (rows 9, 12, 14)
@Sendable private func a2A(_ w: inout QueueWorld) {
    w.playNow("A")
    w.end()
}

let scenarioTable: [QueueScenario] = [
    QueueScenario(
        number: "1", setup: { _ in }, before: "–",
        action: { $0.playNow("A") }, after: "▶ A1 · [A]",
        check: { w in
            #expect(w.lastCommand == w.playCommand("A1"))
            #expect(w.resume("A") == "A1")
            #expect(w.history.isEmpty, "starting on an empty Up Next needs no history entry")
        }),
    QueueScenario(
        number: "2", setup: { $0.playNow("A") }, before: "▶ A1 · [A]",
        action: { $0.playNext("X") }, after: "▶ A1 · X · [A]"),
    QueueScenario(
        number: "3", setup: a1XA, before: "▶ A1 · X · [A]",
        action: { $0.playLast("Y") }, after: "▶ A1 · X · [A] · Y"),
    QueueScenario(
        number: "4", setup: a1XA, before: "▶ A1 · X · [A]",
        action: { _ in }, after: "▶ A1 · X · [A]",
        check: { w in
            #expect(QueueResolver.startAction(preference: .replace, upNextIsEmpty: w.state.isEmpty) == .playNow,
                    "a tap replaces by default (N43)")
            #expect(QueueResolver.startAction(preference: .ask, upNextIsEmpty: w.state.isEmpty) == .askUser)
        }),
    QueueScenario(
        number: "4a", setup: a1XA, before: "▶ A1 · X · [A]",
        action: { $0.append("B") }, after: "▶ A1 · X · [A] · [B]",
        check: { w in
            #expect(w.lastCommand == nil, "appending does not interrupt playback")
            #expect(w.history.isEmpty)
        }),
    QueueScenario(
        number: "4b",
        setup: { w in a1XA(&w); w.setPosition("A1", 750) }, before: "▶ A1 · X · [A]",
        action: { $0.playNow("B") }, after: "▶ B1 · [B]",
        check: { w in
            #expect(w.history.count == 1)
            #expect(w.history.snapshots.first?.reason == .replaced)
            #expect(w.history.snapshots.first.map(w.render) == "▶ A1 · X · [A]")
            #expect(w.position("A1") == 750, "replacing never loses a position")
            #expect(w.resume("A") == "A1", "A remembers where it was")
        }),
    QueueScenario(
        number: "4c", setup: a1XA, before: "▶ A1 · X · [A]",
        action: { $0.playAfterCurrent("B") }, after: "▶ A1 · [B] · X · [A]",
        check: { w in
            var w = w
            #expect(w.lastCommand == nil, "the running episode plays to its end")
            #expect(w.history.isEmpty, "nothing is replaced, so no history entry (A54)")
            #expect(w.resume("A") == "A1")
            w.end()
            #expect(w.render() == "▶ B1 · [B] · X · [A]", "after A1 comes B1")
            #expect(w.resume("A") == "A2", "A remembers A2")
            #expect(w.contents("A") == ["A2", "A3", "A4"])
            #expect(w.playthrough() == ["B2", "B3", "X", "A2", "A3", "A4"])
        }),
    QueueScenario(
        number: "5",
        setup: { w in a1XA(&w); w.setPosition("A1", 750); w.playNow("B") }, before: "▶ B1 · [B]",
        action: { $0.undo() }, after: "▶ A1 · X · [A]",
        check: { w in
            #expect(w.lastCommand == w.playCommand("A1"))
            #expect(w.position("A1") == 750)
            #expect(w.history.count == 2, "restoring writes a history entry, too")
            #expect(w.history.snapshots.first?.reason == .restored)
            #expect(w.history.snapshots.first.map(w.render) == "▶ B1 · [B]")
        }),
    QueueScenario(
        number: "6",
        setup: { w in
            a1XA(&w); w.setPosition("A1", 750); w.playNow("B"); w.end(); w.end()
        },
        before: "▶ B3 · [B]",
        action: { $0.playNow("A") }, after: "▶ A1 · [A]",
        check: { w in
            #expect(w.lastCommand == w.playCommand("A1"))
            #expect(w.position("A1") == 750)
            #expect(w.history.count == 2)
            #expect(w.resume("B") == "B3", "B now remembers B3")
        }),
    QueueScenario(
        number: "7",
        setup: { w in a1XA(&w); w.append("B") }, before: "▶ A1 · X · [A] · [B]",
        action: { $0.clear() }, after: "▶ A1",
        check: { w in
            #expect(w.history.count == 1)
            #expect(w.history.snapshots.first?.reason == .cleared)
            #expect(w.contents("A") == ["A1", "A2", "A3", "A4"], "playlists unchanged")
            #expect(w.contents("B") == ["B1", "B2", "B3"])
            #expect(w.resume("A") == "A1", "clearing keeps the cursor")
            #expect(w.lastCommand == nil, "the running episode keeps playing")
        }),
    QueueScenario(
        number: "8", setup: { $0.playNow("A") }, before: "▶ A1 · [A]",
        action: { $0.end() }, after: "▶ A2 · [A]",
        check: { w in
            #expect(w.contents("A") == ["A2", "A3", "A4"], "A1 removed by the played policy")
            #expect(w.isPlayed("A1"))
            #expect(w.resume("A") == "A2")
        }),
    QueueScenario(
        number: "9", setup: a2A, before: "▶ A2 · [A]",
        action: { $0.skip() }, after: "▶ A3 · A2 · [A]",
        check: { w in
            var w = w
            #expect(!w.isPlayed("A2"), "skipping does not mark as played")
            #expect(w.contents("A") == ["A2", "A3", "A4"], "skipping does not change the playlist")
            w.end()
            #expect(w.render() == "▶ A2 · [A]", "after A3 comes A2")
            w.end()
            #expect(w.render() == "▶ A4 · [A]", "then A4")
        }),
    QueueScenario(
        number: "10",
        setup: { w in a2A(&w); w.setPosition("A2", 310) }, before: "▶ A2 · [A]",
        action: { $0.play("Z") }, after: "▶ Z · [A]",
        check: { w in
            var w = w
            #expect(w.lastCommand == w.playCommand("Z"))
            #expect(w.resume("A") == "A2")
            w.end()
            #expect(w.render() == "▶ A2 · [A]")
            #expect(w.lastCommand == w.playCommand("A2"), "A2 continues at its position")
            #expect(w.position("A2") == 310)
        }),
    QueueScenario(
        number: "11",
        setup: { $0.playNow("B") }, before: "▶ B1 · [B]",
        action: { $0.playNow("A", from: "A3") }, after: "▶ A3 · [A]",
        check: { w in
            #expect(w.resume("A") == "A3")
            #expect(w.history.count == 1)
        }),
    QueueScenario(
        number: "12", setup: a2A, before: "▶ A2 · [A]",
        action: { $0.play("A4", in: "A") }, after: "▶ A4 · [A]",
        check: { w in
            var w = w
            #expect(w.resume("A") == "A4")
            #expect(!w.isPlayed("A2"))
            #expect(w.history.isEmpty, "a jump inside the playlist replaces nothing")
            w.end()
            #expect(w.render() == "▶ A2 · [A]", "after the end of A it starts over with A2")
            w.end()
            #expect(w.render() == "▶ A3 · [A]")
        }),
    QueueScenario(
        number: "13", setup: { _ in }, before: "–",
        action: { $0.playNow("K") }, after: "▶ K1 · [K]",
        check: { w in
            var w = w
            #expect(w.lastCommand == w.playCommand("K1"))
            #expect(w.position("K1") == 0, "played episode starts over")
            w.end()
            #expect(w.render() == "▶ K2 · [K]")
            w.end()
            #expect(w.render() == "▶ K3 · [K]")
            w.end()
            #expect(w.render() == "–", "keep playlist ran through once")
            #expect(w.lastCommand == .stop)
            #expect(w.contents("K") == ["K1", "K2", "K3"], "keep playlist keeps played episodes")
            #expect(w.resume("K") == nil)
        }),
    QueueScenario(
        number: "14", setup: a2A, before: "▶ A2 · [A]",
        action: { $0.addToPlaylist("A", "A5", atTop: false) }, after: "▶ A2 · [A]",
        check: { w in
            var w = w
            #expect(w.playthrough() == ["A3", "A4", "A5"], "the new episode comes after A4")
        }),
]

@Suite("QueueResolver — concept §4.4")
struct QueueResolverScenarioTests {
    @Test(arguments: scenarioTable)
    func scenario(_ s: QueueScenario) {
        var world = QueueWorld()
        s.setup(&world)
        #expect(world.render() == s.before, "setup does not match the 'Vorher' column")
        world.lastCommand = nil
        s.action(&world)
        #expect(world.render() == s.after)
        s.check(world)
    }
}

// MARK: - Special cases below the table and cursor rules

@Suite("QueueResolver — special cases")
struct QueueResolverSpecialCaseTests {
    @Test func episodePlayedInAIsSkippedInB() {
        var w = QueueWorld(extraPlaylists: [("C", .remove, ["S", "C2"])], startPlaylists: [("A", ["A1", "S"])])
        w.playNow("A")
        w.append("C")
        w.end()  // A1
        #expect(w.render() == "▶ S · [A] · [C]")
        w.end()  // S played in A → removed from C as well
        #expect(w.render() == "▶ C2 · [C]")
    }

    @Test func playedEpisodeStillListedInRemovePlaylistIsSkipped() {
        // Defensive: even if the played policy has not been applied yet.
        var w = QueueWorld(extraPlaylists: [("C", .remove, ["S", "C2"])])
        w.markPlayedWithoutPolicy("S")
        w.playNow("C")
        #expect(w.render() == "▶ C2 · [C]")
    }

    @Test func keepPlaylistPlaysEpisodePlayedElsewhere() {
        var w = QueueWorld(extraPlaylists: [("L", .keep, ["S", "L2"])], startPlaylists: [("A", ["S"])])
        w.playNow("A")
        w.end()  // S played in A
        #expect(w.render() == "–")
        w.playNow("L")
        #expect(w.render() == "▶ S · [L]")
        #expect(w.lastCommand == w.playCommand("S"))
        #expect(w.position("S") == 0, "played episode starts over")
    }

    @Test func relisteningAPlayedEpisodeKeepsItsPositionWhenInterrupted() {
        // Review (b): "Replacing and restoring never lose a position" also for played episodes.
        var w = QueueWorld()
        w.playNow("K")
        #expect(w.position("K1") == 0)
        w.setPosition("K1", 600)
        w.playNow("B")
        w.undo()
        #expect(w.render() == "▶ K1 · [K]")
        #expect(w.position("K1") == 600)
        w.play("Z")
        w.end()
        #expect(w.render() == "▶ K1 · [K]")
        #expect(w.position("K1") == 600)
    }

    @Test func episodeMarkedPlayedWhileRunningKeepsItsPlaceUntilItEnds() {
        // Review (b): near-end or manual "played" while running must not lose the cursor.
        var w = QueueWorld()
        w.playNow("A")
        w.end()  // ▶ A2 · [A]
        w.addToPlaylist("A", "A0", atTop: true)
        w.markPlayedWhileRunning()
        #expect(w.contents("A") == ["A0", "A2", "A3", "A4"], "the running episode stays")
        w.end()
        #expect(w.render() == "▶ A3 · [A]", "A1: A0 above the cursor waits for the restart")
        #expect(w.contents("A") == ["A0", "A3", "A4"])
    }

    @Test func playedRunningEpisodeLeavesItsPlaylistWhenReplacedAndTheCursorMovesOn() {
        var w = QueueWorld()
        w.playNow("A", from: "A3")
        w.markPlayedWhileRunning()
        w.playNow("B")
        #expect(w.contents("A") == ["A1", "A2", "A4"])
        #expect(w.resume("A") == "A4")
        w.playNow("A")
        #expect(w.render() == "▶ A4 · [A]", "A remembers where it was (Leitsatz 2)")
    }

    @Test func playedRunningEpisodeInterruptedBySingleEpisodeKeepsTheCursor() {
        var w = QueueWorld()
        w.playNow("A", from: "A3")
        w.addToPlaylist("A", "A0", atTop: true)
        w.markPlayedWhileRunning()
        w.play("Z")
        w.end()
        #expect(w.render() == "▶ A4 · [A]", "neither A1 nor A0 (assumption A1)")
    }

    @Test func undoAfterPlayedRunningEpisodeWasReplaced() {
        var w = QueueWorld()
        w.playNow("A", from: "A3")
        w.setPosition("A3", 3580)
        w.markPlayedWhileRunning()
        w.playNow("B")
        w.undo()
        #expect(w.render() == "▶ A3 · [A]")
        #expect(w.position("A3") == 3580, "the last seconds are not lost")
        w.end()
        #expect(w.render() == "▶ A4 · [A]")
    }

    @Test func episodeInterruptedShortlyBeforeItsEndKeepsItsPosition() {
        var w = QueueWorld()
        w.play("X")
        w.setPosition("X", 3580)
        w.play("Z")
        w.end()
        #expect(w.render() == "▶ X")
        #expect(w.position("X") == 3580)
    }

    @Test func interruptedSingleEpisodeGoesBackToTheFront() {
        var w = QueueWorld()
        w.playNow("A")
        w.playNext("X")
        w.end()  // A1 → X
        #expect(w.render() == "▶ X · [A]")
        w.setPosition("X", 42)
        w.play("Z")
        #expect(w.render() == "▶ Z · X · [A]")
        w.end()
        #expect(w.render() == "▶ X · [A]")
        #expect(w.lastCommand == w.playCommand("X"))
        #expect(w.position("X") == 42)
    }

    @Test func interruptedEpisodeOfAClearedBlockGoesBackToTheFront() {
        var w = QueueWorld()
        w.playNow("A")
        w.clear()
        #expect(w.render() == "▶ A1")
        w.play("Z")
        #expect(w.render() == "▶ Z · A1", "nothing gets lost")
    }

    @Test func appendingAPlaylistAlreadyInUpNextMovesIt() {
        var w = QueueWorld()
        w.playNow("A")
        w.append("B")
        w.playLast("Y")
        #expect(w.render() == "▶ A1 · [A] · [B] · Y")
        w.append("B")
        #expect(w.render() == "▶ A1 · [A] · Y · [B]")
    }

    @Test func playingANewPlaylistNeverDuplicatesABlock() {
        var w = QueueWorld()
        w.playNow("A")
        w.append("B")
        w.playNow("B")
        #expect(w.render() == "▶ B1 · [B]")
    }

    @Test func clearingUpNextKeepsThePlaylistCursor() {
        var w = QueueWorld()
        w.playNow("A")
        w.clear()
        w.end()  // A1 ends without its block
        #expect(w.render() == "–")
        #expect(w.lastCommand == .stop)
        w.playNow("A")
        #expect(w.render() == "▶ A2 · [A]")
    }

    @Test func newEpisodeAboveTheCursorPlaysWhenTheBlockStartsOver() {
        // Assumption A1 (concept §11).
        var w = QueueWorld()
        w.playNow("A")
        w.end()  // ▶ A2 · [A]
        w.addToPlaylist("A", "A0", atTop: true)
        #expect(w.contents("A") == ["A0", "A2", "A3", "A4"])
        #expect(w.playthrough() == ["A3", "A4", "A0"])
    }

    // MARK: Playlists follow the queue (N94, A79; N79 is the first case)

    @Test func playNextInTheRunningPlaylistMovesTheEpisodeBelowTheRunningOne() {
        var w = QueueWorld()
        w.playNow("A")
        w.playNext("A3")
        #expect(w.render() == "▶ A1 · [A]", "the block plays it next, so the single episode leaves (A79)")
        #expect(w.contents("A") == ["A1", "A3", "A2", "A4"])
        #expect(w.resume("A") == "A1")
        #expect(w.playthrough() == ["A3", "A2", "A4"])
    }

    @Test func playNextInTheRunningPlaylistTakesAWaitingCopyOutOfUpNext() {
        var w = QueueWorld()
        w.playNow("A")
        w.playLast("A3")
        #expect(w.contents("A") == ["A1", "A2", "A3", "A4"], "Am Ende changes no playlist")
        w.playNext("A3")
        #expect(w.render() == "▶ A1 · [A]")
        #expect(w.contents("A") == ["A1", "A3", "A2", "A4"])
    }

    /// Something waits in front of the block: the episode stays a single episode, but it
    /// still moves behind the running one in its playlist (A79).
    @Test func playNextInTheRunningPlaylistBehindWaitingItemsStaysASingleEpisode() {
        var w = QueueWorld()
        w.playNow("A")
        w.playNext("X")
        w.playNext("A3")
        #expect(w.render() == "▶ A1 · A3 · X · [A]")
        #expect(w.contents("A") == ["A1", "A3", "A2", "A4"])
        #expect(w.playthrough() == ["A3", "X", "A2", "A4"])
    }

    /// No neighbour of its playlist in Up Next: before the Wiedergabestand, without one at
    /// the top.
    @Test func playNextWithoutNeighboursMovesBeforeTheResumePoint() {
        var w = QueueWorld()
        w.playNow("B")
        w.playNext("A3")
        #expect(w.render() == "▶ B1 · A3 · [B]")
        #expect(w.contents("A") == ["A3", "A1", "A2", "A4"])

        var v = QueueWorld()
        v.playNow("A")
        v.end()
        v.playNow("B")  // A rests at A2
        v.playNext("A4")
        #expect(v.contents("A") == ["A4", "A2", "A3"])
    }

    @Test func playNextOnTheRunningEpisodeChangesNothing() {
        var w = QueueWorld()
        w.playNow("A", from: "A2")
        w.playNext("A2")
        #expect(w.render() == "▶ A2 · [A]")
        #expect(w.contents("A") == ["A1", "A2", "A3", "A4"])
    }

    /// The block would play it first anyway: one place is enough (A79).
    @Test func playNextRightBeforeItsWaitingBlockLeavesItToTheBlock() {
        var w = QueueWorld()
        w.play("X")
        w.append("A")
        w.playNext("A3")
        #expect(w.render() == "▶ X · [A]")
        #expect(w.contents("A") == ["A3", "A1", "A2", "A4"])
        #expect(w.playthrough() == ["A3", "A1", "A2", "A4"])
    }

    /// Florian's example: A3 (playlist A) dragged past A1 (A) and B2 (B) moves behind A1 in
    /// A; B stays as it is.
    @Test func draggingMovesTheEpisodeInItsPlaylistsOnly() {
        var w = QueueWorld()
        w.play("X")
        w.playLast("A3")
        w.playLast("A1")
        w.playLast("B2")
        w.moveItems(from: [0], to: 3)
        #expect(w.render() == "▶ X · A1 · B2 · A3")
        #expect(w.contents("A") == ["A1", "A3", "A2", "A4"])
        #expect(w.contents("B") == ["B1", "B2", "B3"])
    }

    @Test func anEpisodeInTwoPlaylistsMovesInBoth() {
        var w = QueueWorld(extraPlaylists: [("C", .remove, ["C1", "A3", "C2"])])
        w.play("X")
        w.playLast("C2")
        w.playLast("A1")
        w.playLast("A3")
        w.moveItems(from: [2], to: 0)
        #expect(w.render() == "▶ X · A3 · C2 · A1")
        #expect(w.contents("A") == ["A3", "A1", "A2", "A4"])
        #expect(w.contents("C") == ["C1", "A3", "C2"], "A3 already comes before C2")
    }

    @Test func movingABlockChangesNoPlaylist() {
        var w = QueueWorld()
        w.play("X")
        w.playLast("A3")
        w.append("B")
        w.moveItems(from: [1], to: 0)
        #expect(w.render() == "▶ X · [B] · A3")
        #expect(w.contents("A") == ["A1", "A2", "A3", "A4"])
        #expect(w.contents("B") == ["B1", "B2", "B3"])
    }

    /// "Jetzt": the running episode's neighbours are what waits behind it.
    @Test func playNowMovesTheEpisodeBeforeItsWaitingBlock() {
        var w = QueueWorld()
        w.play("X")
        w.append("A")
        w.play("A3")
        #expect(w.render() == "▶ A3 · X · [A]")
        #expect(w.contents("A") == ["A3", "A1", "A2", "A4"])
    }

    @Test func jumpingInsideTheRunningPlaylistChangesNoOrder() {
        var w = QueueWorld()
        w.playNow("A")
        w.play("A3", in: "A")
        #expect(w.render() == "▶ A3 · [A]")
        #expect(w.contents("A") == ["A1", "A2", "A3", "A4"])
    }

    // MARK: New episodes in "Alles" come first (N98, A78, A80)

    /// N: newest first like "Alles" (N97); a new episode arrives at the top.
    private static let newestFirst: [(String, PlayedPolicy, [String])] = [("N", .remove, ["N3", "N2", "N1"])]

    @Test func aNewEpisodePlaysRightAfterTheRunningOne() {
        var w = QueueWorld(extraPlaylists: Self.newestFirst)
        w.playNow("N")
        w.arrive("N", ["N4"])
        #expect(w.render() == "▶ N3 · [N]", "N3 plays on in its block")
        #expect(w.resume("N") == "N4")
        #expect(w.upcoming("N") == ["N4", "N2", "N1"])
        #expect(w.playthrough() == ["N4", "N2", "N1"])
    }

    @Test func severalNewEpisodesPlayNewestFirst() {
        var w = QueueWorld(extraPlaylists: Self.newestFirst)
        w.playNow("N")
        w.arrive("N", ["N5", "N4"])
        #expect(w.playthrough() == ["N5", "N4", "N2", "N1"])
    }

    /// A78: also when the playlist waits or is not in Up Next, it starts at the new episode.
    @Test(arguments: [true, false])
    func aNewEpisodeBecomesTheResumePointOfAPlaylistThatDoesNotRun(waits: Bool) {
        var w = QueueWorld(extraPlaylists: Self.newestFirst)
        w.playNow("N")
        w.playNow("B")
        if waits { w.append("N") }
        w.arrive("N", ["N4"])
        #expect(w.resume("N") == "N4")
        w.playNow("N")
        #expect(w.render() == "▶ N4 · [N]")
        #expect(w.playthrough() == ["N3", "N2", "N1"])
    }

    @Test func skippingWhileANewEpisodeWaitsPlaysIt() {
        var w = QueueWorld(extraPlaylists: Self.newestFirst)
        w.playNow("N")
        w.arrive("N", ["N4"])
        w.skip()
        #expect(w.render() == "▶ N4 · N3 · [N]")
        #expect(w.playthrough() == ["N3", "N2", "N1"])
    }

    /// The block no longer resumes the interrupted episode, so it comes back to the front.
    @Test func anInterruptedEpisodeComesBackWhileANewEpisodeWaits() {
        var w = QueueWorld(extraPlaylists: Self.newestFirst)
        w.playNow("N")
        w.arrive("N", ["N4"])
        w.play("Z")
        #expect(w.render() == "▶ Z · N3 · [N]")
        #expect(w.playthrough() == ["N3", "N4", "N2", "N1"])
    }

    @Test func swipingAwayTheRunningEpisodePlaysTheNewOne() {
        var w = QueueWorld(extraPlaylists: Self.newestFirst)
        w.playNow("N")
        w.arrive("N", ["N4"])
        w.removeNowPlaying()
        #expect(w.render() == "▶ N4 · [N]")
    }

    /// The waiting episode was marked played meanwhile (it stays in a keep playlist): ⏭
    /// goes on after the running episode instead of playing it again.
    @Test func skippingAfterTheNewEpisodeWasPlayedGoesOn() {
        var w = QueueWorld(extraPlaylists: Self.newestFirst)
        w.playNow("N")
        w.arrive("N", ["N4"])
        w.markPlayedWithoutPolicy("N4")
        w.skip()
        #expect(w.render() == "▶ N2 · N3 · [N]")
    }

    @Test func aPlayedArrivalIsSkipped() {
        var w = QueueWorld(extraPlaylists: Self.newestFirst)
        w.playNow("N")
        w.markPlayedWithoutPolicy("N4")
        w.arrive("N", ["N4"])
        #expect(w.resume("N") == "N3")
    }

    @Test func resumeEpisodeRemovedByHandMovesTheCursorOn() {
        // Florian (Slice 2 review): the playlist keeps its place, it does not start over.
        var w = QueueWorld()
        w.playNow("A", from: "A3")
        w.playNow("B")
        w.removeFromPlaylist("A", "A3")
        #expect(w.resume("A") == "A4")
        w.playNow("A")
        #expect(w.render() == "▶ A4 · [A]")
    }

    @Test func runningEpisodeRemovedByHandPlaysToItsEndThenTheBlockContinues() {
        var w = QueueWorld()
        w.playNow("A", from: "A2")
        w.removeFromPlaylist("A", "A2")
        #expect(w.render() == "▶ A2 · [A]")
        #expect(w.resume("A") == "A3")
        w.end()
        #expect(w.render() == "▶ A3 · [A]")
        #expect(w.playthrough() == ["A4", "A1"])
    }

    @Test func runningLastEpisodeOfAKeepPlaylistRemovedByHandEndsTheBlock() {
        var w = QueueWorld()
        w.playNow("K", from: "K3")
        w.removeFromPlaylist("K", "K3")
        #expect(w.render() == "▶ K3")
        w.end()
        #expect(w.render() == "–")
    }

    @Test func removingAnotherEpisodeByHandLeavesTheCursor() {
        var w = QueueWorld()
        w.playNow("A", from: "A2")
        w.removeFromPlaylist("A", "A3")
        #expect(w.resume("A") == "A2")
        w.end()
        #expect(w.render() == "▶ A4 · [A]")
    }

    @Test func skipASingleEpisode() {
        var w = QueueWorld()
        w.playNow("A")
        w.end()  // ▶ A2 · [A]
        w.play("Z")
        w.skip()
        #expect(w.render() == "▶ A2 · Z · [A]")
        #expect(!w.isPlayed("Z"))
    }

    @Test func skipWithoutNextEpisodeStopsAndKeepsTheEpisode() {
        var w = QueueWorld()
        w.play("Z")
        w.skip()
        #expect(w.render() == "▶ Z")
        #expect(w.lastCommand == .stop)
        #expect(!w.isPlayed("Z"))
    }

    @Test func skipTheLastEpisodeOfAKeepPlaylistStops() {
        var w = QueueWorld()
        w.playNow("K", from: "K3")
        w.skip()
        #expect(w.render() == "▶ K3 · [K]")
        #expect(w.lastCommand == .stop)
    }

    @Test func removePlaylistStartsOverWithTheFirstUnplayedEpisode() {
        var w = QueueWorld()
        w.playNow("A", from: "A3")
        #expect(w.playthrough() == ["A4", "A1", "A2"])
        #expect(w.render() == "–")
        #expect(w.contents("A") == [])
    }

    @Test func lastEpisodeEndingStopsPlayback() {
        var w = QueueWorld()
        w.play("Z")
        w.end()
        #expect(w.render() == "–")
        #expect(w.lastCommand == .stop)
    }

    @Test func singleEpisodePlayedInsteadOfABlockEpisodeKeepsTheBlockCursor() {
        // ▶ on a row of a playlist that is in Up Next but not running = scenario 10.
        var w = QueueWorld()
        w.playNow("A")
        w.append("B")
        w.play("B2", in: "B")
        #expect(w.render() == "▶ B2 · [A] · [B]")
        #expect(w.resume("B") == nil)
    }

    @Test func playlistFromHereWhileItIsRunningDetachesTheRunningEpisode() {
        var w = QueueWorld()
        w.playNow("A")
        w.append("A", from: "A3")
        #expect(w.render() == "▶ A1 · [A]")
        #expect(w.resume("A") == "A3")
        w.end()  // A1 no longer advances A's cursor
        #expect(w.render() == "▶ A3 · [A]")
    }

    @Test func skipInBlockBehindASingleEpisodeAdvancesTheCursor() {
        var w = QueueWorld()
        w.playNow("K", from: "K2")
        w.playNext("X")
        #expect(w.render() == "▶ K2 · X · [K]")
        w.skip()
        #expect(w.render() == "▶ X · K2 · [K]")
        #expect(w.resume("K") == "K3", "K2 must not play twice in a keep playlist")
    }

    @Test func playlistFromHereAppendedBehindAnotherPlaylist() {
        var w = QueueWorld()
        w.playNow("B")
        w.append("A", from: "A3")
        #expect(w.render() == "▶ B1 · [B] · [A]")
        #expect(w.resume("A") == "A3")
        #expect(w.history.isEmpty)
    }

    @Test func upNextWithOnlyARunningEpisodeIsNotEmpty() {
        // After "Up Next leeren" the running episode keeps playing: starting another
        // playlist still asks and the replacement goes to the history.
        var w = QueueWorld()
        w.playNow("A")
        w.clear()
        #expect(w.render() == "▶ A1")
        #expect(QueueResolver.startAction(preference: .ask, upNextIsEmpty: w.state.isEmpty) == .askUser)
        w.playNow("B")
        #expect(w.history.count == 2)
        #expect(w.history.snapshots.first.map(w.render) == "▶ A1")
    }

    @Test func clearingWithoutItemsWritesNoHistory() {
        var w = QueueWorld()
        w.play("Z")
        w.clear()
        #expect(w.render() == "▶ Z")
        #expect(w.history.isEmpty)
    }

    @Test func appendingToAnEmptyUpNextStartsThePlaylist() {
        var w = QueueWorld()
        w.append("A")
        #expect(w.render() == "▶ A1 · [A]")
    }

    @Test func emptyPlaylistBlockIsDropped() {
        var w = QueueWorld(extraPlaylists: [("E", .remove, [])])
        w.playNow("A")
        w.append("E")
        w.append("B")
        w.playthroughOnce(4)  // A1…A4
        #expect(w.render() == "▶ B1 · [B]")
    }

    // MARK: "Nach der aktuellen Folge" (scenario 4c, A54, A61)

    @Test func afterCurrentMovesAPlaylistAlreadyInUpNext() {
        var w = QueueWorld()
        w.playNow("A")
        w.append("B")
        w.playNext("X")
        #expect(w.render() == "▶ A1 · X · [A] · [B]")
        w.playAfterCurrent("B")
        #expect(w.render() == "▶ A1 · [B] · X · [A]", "a block never stands twice in Up Next")
    }

    @Test func afterCurrentOnTheRunningPlaylistMovesItsBlockToTheFront() {
        var w = QueueWorld()
        w.playNow("A")
        w.playNext("X")
        w.playAfterCurrent("A")
        #expect(w.render() == "▶ A1 · [A] · X")
        #expect(w.lastCommand == nil)
        w.end()
        #expect(w.render() == "▶ A2 · [A] · X", "the running block goes on after its episode")
    }

    @Test func afterCurrentBehindASingleEpisode() {
        var w = QueueWorld()
        w.playNow("A")
        w.play("Z")
        #expect(w.render() == "▶ Z · [A]")
        w.playAfterCurrent("B")
        #expect(w.render() == "▶ Z · [B] · [A]")
        w.end()
        #expect(w.render() == "▶ B1 · [B] · [A]")
        #expect(w.resume("A") == "A1", "A was not running and keeps its cursor")
    }

    @Test func afterCurrentFromHereWhileAnotherPlaylistRuns() {
        var w = QueueWorld()
        w.playNow("B")
        w.playAfterCurrent("A", from: "A3")
        #expect(w.render() == "▶ B1 · [A] · [B]")
        #expect(w.resume("A") == "A3")
        w.end()
        #expect(w.render() == "▶ A3 · [A] · [B]")
        #expect(w.resume("B") == "B2")
    }

    /// "Playlist ab hier" + "Nach der aktuellen Folge" on another episode of the running
    /// playlist: the running episode plays to its end as a single episode, then the playlist
    /// goes on at the chosen episode (like scenario 11 without replacing).
    @Test func afterCurrentFromHereOnTheRunningPlaylist() {
        var w = QueueWorld()
        w.playNow("A")
        w.playNext("X")
        w.playAfterCurrent("A", from: "A3")
        #expect(w.render() == "▶ A1 · [A] · X")
        #expect(w.resume("A") == "A3")
        w.end()
        #expect(w.render() == "▶ A3 · [A] · X")
    }

    /// A61: "Playlist ab hier" on exactly the running episode: it becomes the block's episode
    /// and the playlist goes on after it; a keep playlist does not play it twice. "Jetzt"
    /// already moved it to the top of its playlist (N94: no neighbour, no Wiedergabestand).
    @Test(arguments: [("K", "K2", ["K1", "K3"]), ("A", "A2", ["A1", "A3", "A4"])])
    func afterCurrentFromTheRunningEpisodeJoinsTheBlock(playlist: String, episode: String, upcoming: [String]) {
        var w = QueueWorld()
        w.play(episode)
        #expect(w.render() == "▶ \(episode)")
        w.playAfterCurrent(playlist, from: episode)
        #expect(w.render() == "▶ \(episode) · [\(playlist)]")
        #expect(w.lastCommand == nil, "the running episode is not restarted")
        #expect(w.resume(playlist) == episode)
        #expect(w.upcoming(playlist) == upcoming)
        w.end()
        #expect(w.render() == "▶ \(upcoming[0]) · [\(playlist)]")
    }

    /// A53, A61: with nothing running the playlist simply starts.
    @Test func afterCurrentOnAnEmptyUpNextStartsThePlaylist() {
        var w = QueueWorld()
        w.playAfterCurrent("A")
        #expect(w.render() == "▶ A1 · [A]")
        #expect(w.lastCommand == w.playCommand("A1"))
        #expect(w.history.isEmpty)
    }

    @Test func afterCurrentWithAKeepPlaylist() {
        var w = QueueWorld()
        w.playNow("A")
        w.playAfterCurrent("K")
        #expect(w.render() == "▶ A1 · [K] · [A]")
        #expect(w.playthrough() == ["K1", "K2", "K3", "A2", "A3", "A4"])
    }

    @Test func afterCurrentWithAnEmptyPlaylistChangesNothingThatPlays() {
        var w = QueueWorld(extraPlaylists: [("E", .remove, [])])
        w.playNow("A")
        w.playAfterCurrent("E")
        #expect(w.render() == "▶ A1 · [E] · [A]")
        w.end()
        #expect(w.render() == "▶ A2 · [A]", "the empty block is dropped")
    }

    @Test func afterCurrentWithAnEmptyPlaylistOnAnEmptyUpNext() {
        var w = QueueWorld(extraPlaylists: [("E", .remove, [])])
        w.playAfterCurrent("E")
        #expect(w.render() == "–")
        #expect(w.lastCommand == .stop)
    }

    /// A61 with the block already waiting behind other items.
    @Test func afterCurrentFromTheRunningEpisodeOfTheRunningBlockMovesTheBlock() {
        var w = QueueWorld()
        w.playNow("K", from: "K2")
        w.playNext("X")
        #expect(w.render() == "▶ K2 · X · [K]")
        w.playAfterCurrent("K", from: "K2")
        #expect(w.render() == "▶ K2 · [K] · X")
        #expect(w.lastCommand == nil)
        #expect(w.upcoming("K") == ["K3"])
    }

    /// A61 when the running episode comes from another block C: it joins L, and C moves on
    /// past it as if it had ended there (Leitsatz 2), so C never plays it a second time.
    @Test func afterCurrentFromTheRunningEpisodeOfAnotherBlock() {
        var w = QueueWorld(extraPlaylists: [("C", .keep, ["S", "C2"]), ("L", .keep, ["L1", "S", "L3"])])
        w.playNow("C")
        #expect(w.render() == "▶ S · [C]")
        w.playAfterCurrent("L", from: "S")
        #expect(w.render() == "▶ S · [L] · [C]")
        #expect(w.resume("L") == "S")
        #expect(w.resume("C") == "C2")
        #expect(w.playthrough() == ["L3", "C2"])
    }

    @Test func skipWhileAPlaylistWaitsAfterTheCurrentEpisode() {
        var w = QueueWorld()
        w.playNow("A")
        w.playAfterCurrent("B")
        w.skip()
        #expect(w.render() == "▶ B1 · A1 · [B] · [A]", "the skipped episode comes right after the next one (N4)")
    }

    // MARK: Taking back "Als Nächstes" (undo in the inbox, N50)

    @Test func withdrawAWaitingEpisode() {
        var w = QueueWorld()
        w.playNow("A")
        w.playNext("X")
        w.withdraw("X")
        #expect(w.render() == "▶ A1 · [A]")
        #expect(w.lastCommand == nil)
    }

    /// A22 cued it on an empty Up Next: taking it back empties Up Next again.
    @Test func withdrawTheCuedEpisodeOfAnEmptyUpNext() {
        var w = QueueWorld()
        w.playNext("X")
        #expect(w.render() == "▶ X")
        w.withdraw("X", isPlaying: false)
        #expect(w.render() == "–")
        #expect(w.lastCommand == .stop)
    }

    /// A cued (paused) episode with something behind it: the next item is cued instead.
    @Test func withdrawTheCuedEpisodeCuesTheNextItem() {
        var w = QueueWorld()
        w.playNext("X")
        w.playLast("Y")
        #expect(w.render() == "▶ X · Y")
        w.withdraw("X", isPlaying: false)
        #expect(w.render() == "▶ Y")
        #expect(w.lastCommand == .cue(QueueWorld.episode("Y")))
    }

    /// Once the episode plays (it came up from the queue, or was started), it plays on.
    @Test func withdrawLeavesAPlayingEpisode() {
        var w = QueueWorld(startPlaylists: [("A", ["A1"])])
        w.playNow("A")
        w.playLast("X")
        w.end()
        #expect(w.render() == "▶ X")
        w.withdraw("X", isPlaying: true)
        #expect(w.render() == "▶ X")
        #expect(w.lastCommand == nil)
    }

    @Test func anEpisodeOfABlockIsNeverWithdrawn() {
        var w = QueueWorld()
        w.playNow("A")
        w.withdraw("A1", isPlaying: false)
        #expect(w.render() == "▶ A1 · [A]")
    }

    // MARK: Removing the running episode from Up Next (Florian, after Slice 8)

    /// Like ⏭ without the skipped episode coming back: the next item plays.
    @Test func removeTheRunningSingleEpisodePlaysTheNextItem() {
        var w = QueueWorld()
        w.playNow("A")
        w.play("Z")
        #expect(w.render() == "▶ Z · [A]")
        w.removeNowPlaying()
        #expect(w.render() == "▶ A1 · [A]")
        #expect(w.lastCommand == w.playCommand("A1"))
        #expect(!w.isPlayed("Z"))
    }

    /// The block's cursor moves on; the episode stays in the playlist, unplayed, with its position.
    @Test func removeTheRunningEpisodeOfABlockMovesTheCursorOn() {
        var w = QueueWorld()
        w.playNow("A")
        w.setPosition("A1", 300)
        w.removeNowPlaying()
        #expect(w.render() == "▶ A2 · [A]")
        #expect(w.resume("A") == "A2")
        #expect(w.contents("A") == ["A1", "A2", "A3", "A4"])
        #expect(!w.isPlayed("A1"))
        #expect(w.position("A1") == 300)
    }

    /// A "remove" playlist starts over after its last episode, as when it ends.
    @Test func removeTheLastRunningEpisodeOfARemovePlaylistStartsItOver() {
        var w = QueueWorld()
        w.playNow("A", from: "A4")
        w.removeNowPlaying()
        #expect(w.render() == "▶ A1 · [A]")
    }

    @Test func removeTheLastRunningEpisodeOfAKeepPlaylistEndsTheBlock() {
        var w = QueueWorld()
        w.playNow("K", from: "K3")
        w.playLast("X")
        w.removeNowPlaying()
        #expect(w.render() == "▶ X")
        #expect(w.resume("K") == nil)
    }

    /// Paused: the next item is only cued.
    @Test func removeThePausedEpisodeCuesTheNextItem() {
        var w = QueueWorld()
        w.playNext("X")
        w.playLast("Y")
        w.removeNowPlaying(isPlaying: false)
        #expect(w.render() == "▶ Y")
        #expect(w.lastCommand == .cue(QueueWorld.episode("Y")))
    }

    @Test func removeTheOnlyEpisodeEmptiesUpNext() {
        var w = QueueWorld()
        w.play("Z")
        w.removeNowPlaying()
        #expect(w.render() == "–")
        #expect(w.lastCommand == .stop)
    }

    @Test func upNextNeverChangesPlaylistContent() {
        // Only the played policy (applied by the service) changes content; the
        // resolver's operations alone never do. The order may follow the queue (N94).
        var w = QueueWorld()
        let before = w.allContents
        w.playNow("A")
        w.playNext("X")
        w.append("B")
        w.skip()
        w.play("A4", in: "A")
        w.play("Z")
        w.clear()
        w.playNow("B", from: "B2")
        w.undo()
        w.playLast("Y")
        #expect(w.allContents.mapValues(Set.init) == before.mapValues(Set.init))
    }
}

@Suite("QueueResolver — starting a playlist (concept §4.4, N43)")
struct PlaylistStartActionTests {
    /// N43, A52: a tap replaces (default) or asks; on an empty Up Next it always just starts.
    @Test(arguments: [
        (PlaylistStartPreference.replace, false, PlaylistStartAction.playNow),
        (.replace, true, .playNow),
        (.ask, false, .askUser),
        (.ask, true, .playNow),
    ])
    func startAction(preference: PlaylistStartPreference, upNextIsEmpty: Bool, expected: PlaylistStartAction) {
        #expect(QueueResolver.startAction(preference: preference, upNextIsEmpty: upNextIsEmpty) == expected)
    }

    /// N52: every value stored before Slice 7 becomes "Ersetzen" once; the setting lives under
    /// a new key, so a value chosen afterwards stays.
    @Test(arguments: [nil, "ask", "playNow", "append"])
    func formerSettingBecomesReplace(stored: String?) throws {
        let defaults = try #require(UserDefaults(suiteName: "start-\(UUID().uuidString)"))
        defaults.set(stored, forKey: "playlistStartPreference")
        #expect(PlaylistStartPreference.stored(in: defaults) == .replace)
        defaults.set(PlaylistStartPreference.ask.rawValue, forKey: PlaylistStartPreference.storageKey)
        #expect(PlaylistStartPreference.stored(in: defaults) == .ask)
    }
}

// MARK: - Test world: a minimal stand-in for UpNextService

/// Holds the persistent state (Up Next, playlists with cursors, played flags, positions,
/// history), builds a fresh `QueueResolver` for every operation like the service will,
/// and applies the played policy after an episode ended.
struct QueueWorld {
    private(set) var state = UpNextState()
    private(set) var history = UpNextHistory()
    private var playlists: [String: QueuePlaylist] = [:]
    private var played: Set<String> = []
    private var positions: [String: TimeInterval] = [:]
    var lastCommand: PlaybackCommand?
    private var now = Date(timeIntervalSinceReferenceDate: 0)

    /// A, B: "remove" playlists A1–A4, B1–B3. K: "keep" playlist K1–K3, K1 already played.
    init(
        extraPlaylists: [(String, PlayedPolicy, [String])] = [],
        startPlaylists: [(String, [String])]? = nil
    ) {
        var defs: [(String, PlayedPolicy, [String])] = [
            ("A", .remove, ["A1", "A2", "A3", "A4"]),
            ("B", .remove, ["B1", "B2", "B3"]),
            ("K", .keep, ["K1", "K2", "K3"]),
        ]
        for (name, episodes) in startPlaylists ?? [] {
            if let i = defs.firstIndex(where: { $0.0 == name }) { defs[i].2 = episodes }
        }
        for (name, policy, episodes) in defs + extraPlaylists {
            playlists[name] = QueuePlaylist(
                id: Self.playlist(name), playedPolicy: policy,
                episodes: episodes.map(Self.episode), resumeEpisode: nil)
        }
        played = ["K1"]
    }

    // Names ↔ IDs: the name is encoded in the UUID, so no registry is needed.
    static func episode(_ name: String) -> EpisodeID { EpisodeID(uuid(name)) }
    static func playlist(_ name: String) -> PlaylistID { PlaylistID(uuid(name)) }

    private static func uuid(_ name: String) -> UUID {
        var bytes = Array(name.utf8.prefix(16))
        bytes += Array(repeating: 0, count: 16 - bytes.count)
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    static func name(_ uuid: UUID) -> String {
        withUnsafeBytes(of: uuid.uuid) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }

    // MARK: Operations (each one = one service call)

    mutating func playNow(_ playlist: String, from episode: String? = nil) {
        run { r, h, now in r.playNow(playlist: Self.playlist(playlist), startingAt: episode.map(Self.episode), history: &h, now: now) }
    }

    mutating func append(_ playlist: String, from episode: String? = nil) {
        run { r, _, _ in r.append(playlist: Self.playlist(playlist), startingAt: episode.map(Self.episode)) }
    }

    /// "Nach der aktuellen Folge" (scenario 4c).
    mutating func playAfterCurrent(_ playlist: String, from episode: String? = nil) {
        run { r, _, _ in r.playAfterCurrent(playlist: Self.playlist(playlist), startingAt: episode.map(Self.episode)) }
    }

    /// Takes back "Als Nächstes" / "Am Ende" (undo).
    mutating func withdraw(_ episode: String, isPlaying: Bool = true) {
        run { r, _, _ in r.withdraw(Self.episode(episode), isPlaying: isPlaying) }
    }

    /// "Als Nächstes"; the episode's playlists follow the queue (N94).
    mutating func playNext(_ episode: String) {
        let id = Self.episode(episode)
        let containing = containing(id)
        run { r, _, _ in
            let command = r.playNext(id)
            r.episodeWasPlaced(id, in: containing)
            return command
        }
    }

    mutating func playLast(_ episode: String) {
        run { r, _, _ in r.playLast(Self.episode(episode)) }
    }

    /// Swiped away in Up Next: "X" for a single episode, "[A]" for a block.
    mutating func remove(_ item: String) {
        let parsed = Self.item(item)
        run { r, _, _ in r.remove(parsed); return nil }
    }

    /// The running episode swiped away in Up Next.
    mutating func removeNowPlaying(isPlaying: Bool = true) {
        run { r, _, _ in r.removeNowPlaying(isPlaying: isPlaying) }
    }

    /// Dragging in Up Next; the playlists of dragged single episodes follow (N94).
    mutating func moveItems(from offsets: IndexSet, to destination: Int) {
        let moved = offsets.compactMap { index -> EpisodeID? in
            guard case .episode(let id) = state.items[index] else { return nil }
            return id
        }
        let containing = moved.map { ($0, containing($0)) }
        run { r, _, _ in
            r.moveItems(fromOffsets: offsets, toOffset: destination)
            for (id, playlists) in containing { r.episodeWasPlaced(id, in: playlists) }
            return nil
        }
    }

    /// The playlist is about to be deleted (PlaylistService), then it is gone.
    mutating func deletePlaylist(_ playlist: String) {
        let id = Self.playlist(playlist)
        playlists[playlist] = nil
        run(policyStep: true) { r, _, _ in r.playlistWillBeDeleted(id); return nil }
    }

    /// "▶ Abspielen"; unless it jumps inside the running playlist, the episode's playlists
    /// follow the queue (N94).
    mutating func play(_ episode: String, in playlist: String? = nil) {
        let id = Self.episode(episode)
        let containing = containing(id)
        run { r, _, _ in
            let command = r.play(id, inPlaylist: playlist.map(Self.playlist))
            if r.state.nowPlaying?.playlist == nil { r.episodeWasPlaced(id, in: containing) }
            return command
        }
    }

    mutating func skip() {
        run { r, _, _ in r.skip() }
    }

    mutating func clear() {
        run { r, h, now in r.clear(history: &h, now: now); return nil }
    }

    mutating func undo() {
        guard let latest = history.snapshots.first else { return }
        run { r, h, now in r.restore(latest, history: &h, now: now) }
    }

    /// The running episode reached its end: resolve the successor first, then mark it
    /// played and apply the played policy (concept §4.4, "Folge E endet").
    mutating func end() {
        guard let ended = state.nowPlaying?.episode else { return }
        let name = Self.name(ended.uuid)
        run { r, _, _ in r.episodeEnded() }
        played.insert(name)
        positions[name] = 0  // heard to the end → starts over next time
        applyPlayedPolicy()
    }

    /// Near-end threshold reached or marked played by hand while the episode runs.
    mutating func markPlayedWhileRunning() {
        guard let running = state.nowPlaying?.episode else { return }
        played.insert(Self.name(running.uuid))
        applyPlayedPolicy()
    }

    /// The service's played policy: removes played episodes from "remove" playlists,
    /// except the running one, after moving cursors on.
    private mutating func applyPlayedPolicy() {
        for name in played.sorted() {
            let id = Self.episode(name)
            let containing = playlists.values.filter { $0.episodes.contains(id) }
                .map { PlaylistPolicy(playlistID: $0.id, policy: $0.playedPolicy) }
            let remove = PlayedRules.playlistsToRemoveFrom(containing, isNowPlaying: state.nowPlaying?.episode == id)
            guard !remove.isEmpty else { continue }
            run(policyStep: true) { r, _, _ in r.playedEpisodeWillBeRemoved(id, from: remove); return nil }
            for (key, playlist) in playlists where remove.contains(playlist.id) {
                playlists[key]?.episodes.removeAll { $0 == id }
            }
        }
    }

    /// Ends episodes until playback stops; returns the episodes that played after the current one.
    mutating func playthrough() -> [String] {
        var names: [String] = []
        while state.nowPlaying != nil {
            end()
            if let next = state.nowPlaying { names.append(Self.name(next.episode.uuid)) }
        }
        return names
    }

    mutating func playthroughOnce(_ count: Int) {
        for _ in 0..<count { end() }
    }

    // MARK: Playlist content and episode state (changed by other services)

    mutating func addToPlaylist(_ playlist: String, _ episode: String, atTop: Bool) {
        if atTop {
            playlists[playlist]?.episodes.insert(Self.episode(episode), at: 0)
        } else {
            playlists[playlist]?.episodes.append(Self.episode(episode))
        }
    }

    /// New episodes reached a newest-first playlist at its top (the service's part of N98).
    mutating func arrive(_ playlist: String, _ episodes: [String]) {
        playlists[playlist]?.episodes.insert(contentsOf: episodes.map(Self.episode), at: 0)
        let id = Self.playlist(playlist)
        let arrived = Set(episodes.map(Self.episode))
        run(policyStep: true) { r, _, _ in r.episodesArrived(arrived, in: id); return nil }
    }

    /// Removed by hand: the cursor moves on first, like for the played policy.
    mutating func removeFromPlaylist(_ playlist: String, _ episode: String) {
        let id = Self.episode(episode)
        guard let playlistID = playlists[playlist]?.id else { return }
        run(policyStep: true) { r, _, _ in r.episodeWillBeRemoved(id, from: [playlistID]); return nil }
        playlists[playlist]?.episodes.removeAll { $0 == id }
    }

    /// Several episodes leave at once ("Alles" after leaving out a playlist or podcast).
    mutating func removeSeveralFromPlaylist(_ playlist: String, _ episodes: [String]) {
        let ids = Set(episodes.map(Self.episode))
        guard let playlistID = playlists[playlist]?.id else { return }
        run(policyStep: true) { r, _, _ in r.episodesWillBeRemoved(ids, from: playlistID); return nil }
        playlists[playlist]?.episodes.removeAll { ids.contains($0) }
    }

    mutating func markPlayedWithoutPolicy(_ episode: String) { played.insert(episode) }
    mutating func setPosition(_ episode: String, _ seconds: TimeInterval) { positions[episode] = seconds }

    // MARK: Reading

    func render() -> String { render(state) }

    func render(_ snapshot: UpNextSnapshotValue) -> String { render(snapshot.state) }

    func render(_ state: UpNextState) -> String {
        var parts: [String] = []
        if let now = state.nowPlaying { parts.append("▶ " + Self.name(now.episode.uuid)) }
        for item in state.items {
            switch item {
            case .episode(let id): parts.append(Self.name(id.uuid))
            case .playlist(let id): parts.append("[\(Self.name(id.uuid))]")
            }
        }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }

    /// The episodes a block will play, as Up Next shows them.
    func upcoming(_ playlist: String) -> [String] {
        let resolver = QueueResolver(
            state: state, playlists: Array(playlists.values), playedEpisodes: Set(played.map(Self.episode)))
        return resolver.upcomingEpisodes(of: Self.playlist(playlist)).map { Self.name($0.uuid) }
    }

    func resume(_ playlist: String) -> String? {
        playlists[playlist]?.resumeEpisode.map { Self.name($0.uuid) }
    }

    func contents(_ playlist: String) -> [String] {
        playlists[playlist]?.episodes.map { Self.name($0.uuid) } ?? []
    }

    var allContents: [String: [String]] { playlists.mapValues { $0.episodes.map { Self.name($0.uuid) } } }

    func isPlayed(_ episode: String) -> Bool { played.contains(episode) }
    func position(_ episode: String) -> TimeInterval { positions[episode] ?? 0 }

    static func item(_ text: String) -> UpNextItem {
        text.hasPrefix("[") ? .playlist(playlist(String(text.dropFirst().dropLast()))) : .episode(episode(text))
    }

    func playCommand(_ episode: String) -> PlaybackCommand {
        .play(Self.episode(episode))
    }

    // MARK: Plumbing

    /// The playlists that hold the episode, which follow the queue (N94).
    private func containing(_ episode: EpisodeID) -> [PlaylistID] {
        playlists.values.filter { $0.episodes.contains(episode) }.map(\.id)
    }

    private mutating func run(
        policyStep: Bool = false,
        _ operation: (inout QueueResolver, inout UpNextHistory, Date) -> PlaybackCommand?
    ) {
        now += 60
        var resolver = QueueResolver(
            state: state,
            playlists: Array(playlists.values),
            playedEpisodes: Set(played.map(Self.episode)))
        let command = operation(&resolver, &history, now)
        if !policyStep { lastCommand = command }
        state = resolver.state
        for (key, playlist) in playlists {
            let updated = resolver.playlists[playlist.id]
            #expect(updated.map { Set($0.episodes) } == Set(playlist.episodes), "Up Next never changes a playlist's content")
            playlists[key]?.episodes = updated?.episodes ?? playlist.episodes
            playlists[key]?.resumeEpisode = updated?.resumeEpisode
        }
        if !policyStep { applyPlayedPolicy() }
    }
}
