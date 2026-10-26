import Foundation
import Testing
@testable import PodlistKit

// Concept §4.4 (v0.7, N104–N107) as tests. Every row of the scenario table is one argument
// of `flatScenarioTable`; the special cases below the table, the resume point (N107) and the
// playlist view's split (N106) follow. Notation as in the concept: "▶ A1 · X · A2" = A1
// plays, then X, then A2. "–" = Up Next is empty. There are no blocks any more.
//
// These tests describe the new `QueueResolver` API (docs/plan-warteschlange-v07.md) and
// compile once step 1 of the slice delivers it.

// MARK: - Scenario table

struct FlatQueueScenario: Sendable, CustomTestStringConvertible {
    let number: String
    /// Builds the "Vorher" state from an empty Up Next.
    let setup: @Sendable (inout UpNextWorld) -> Void
    let before: String
    let action: @Sendable (inout UpNextWorld) -> Void
    let after: String
    /// Further expectations of the row (positions, history, playlist content, follow-ups).
    var check: @Sendable (UpNextWorld) -> Void = { _ in }

    var testDescription: String { "Szenario \(number)" }
}

/// ▶ A1 · X · A2 · A3 · A4  (rows 3–5, 7, 16)
@Sendable private func a1X(_ w: inout UpNextWorld) {
    w.playNow("A")
    w.playNext("X")
}

/// ▶ A2 · A3 · A4 with A1 played and removed from A (rows 4e, 9, 10, 12, 14)
@Sendable private func a2(_ w: inout UpNextWorld) {
    w.playNow("A")
    w.end()
}

let flatScenarioTable: [FlatQueueScenario] = [
    FlatQueueScenario(
        number: "1", setup: { _ in }, before: "–",
        action: { $0.playNow("A") }, after: "▶ A1 · A2 · A3 · A4",
        check: { w in
            #expect(w.lastCommand == w.playCommand("A1"))
            #expect(w.resume("A") == "A1")
            #expect(w.history.isEmpty, "starting on an empty Up Next needs no history entry")
            #expect(w.live("A") == ["A1", "A2", "A3", "A4"] && w.draft("A").isEmpty, "the whole playlist is live (N106)")
        }),
    FlatQueueScenario(
        number: "2", setup: { $0.playNow("A") }, before: "▶ A1 · A2 · A3 · A4",
        action: { $0.playNext("X") }, after: "▶ A1 · X · A2 · A3 · A4",
        check: { w in
            #expect(w.contents("A") == ["A1", "A2", "A3", "A4"], "A is untouched")
            #expect(w.live("A") == ["A1", "A2", "A3", "A4"], "X is not in A")
        }),
    FlatQueueScenario(
        number: "2a", setup: { $0.playNow("A") }, before: "▶ A1 · A2 · A3 · A4",
        action: { $0.playNext("A3") }, after: "▶ A1 · A3 · A2 · A4",
        check: { w in
            #expect(w.contents("A") == ["A1", "A2", "A3", "A4"], "A keeps its order: the queue never rewrites a playlist (N104)")
            #expect(w.live("A") == ["A1", "A3", "A2", "A4"], "the view of A shows the queue's order on top (N106)")
            #expect(w.lastCommand == nil)
        }),
    FlatQueueScenario(
        number: "3", setup: a1X, before: "▶ A1 · X · A2 · A3 · A4",
        action: { $0.playLast("Y") }, after: "▶ A1 · X · A2 · A3 · A4 · Y"),
    FlatQueueScenario(
        number: "3a", setup: { $0.playNow("A") }, before: "▶ A1 · A2 · A3 · A4",
        action: { $0.playLast("A2") }, after: "▶ A1 · A3 · A4 · A2",
        check: { w in #expect(w.contents("A") == ["A1", "A2", "A3", "A4"]) }),
    FlatQueueScenario(
        number: "4", setup: a1X, before: "▶ A1 · X · A2 · A3 · A4",
        action: { _ in }, after: "▶ A1 · X · A2 · A3 · A4",
        check: { w in
            #expect(QueueResolver.startAction(preference: .replace, upNextIsEmpty: w.state.isEmpty) == .playNow,
                    "a tap replaces by default (N43)")
            #expect(QueueResolver.startAction(preference: .ask, upNextIsEmpty: w.state.isEmpty) == .askUser)
        }),
    FlatQueueScenario(
        number: "4a", setup: a1X, before: "▶ A1 · X · A2 · A3 · A4",
        action: { $0.append("B") }, after: "▶ A1 · X · A2 · A3 · A4 · B1 · B2 · B3",
        check: { w in
            #expect(w.lastCommand == nil, "appending does not interrupt playback")
            #expect(w.history.isEmpty)
            #expect(w.resume("B") == "B1", "B's resume point is its frontmost episode in the queue (N107)")
        }),
    FlatQueueScenario(
        number: "4b",
        setup: { w in a1X(&w); w.setPosition("A1", 750) }, before: "▶ A1 · X · A2 · A3 · A4",
        action: { $0.playNow("B") }, after: "▶ B1 · B2 · B3",
        check: { w in
            #expect(w.history.count == 1)
            #expect(w.history.snapshots.first?.reason == .replaced)
            #expect(w.history.snapshots.first.map(w.render) == "▶ A1 · X · A2 · A3 · A4")
            #expect(w.position("A1") == 750, "replacing never loses a position")
            #expect(w.resume("A") == "A1", "A remembers where it was (N107)")
            #expect(w.lastCommand == w.playCommand("B1"))
        }),
    FlatQueueScenario(
        number: "4c", setup: a1X, before: "▶ A1 · X · A2 · A3 · A4",
        action: { $0.playAfterCurrent("B") }, after: "▶ A1 · B1 · B2 · B3 · X · A2 · A3 · A4",
        check: { w in
            #expect(w.lastCommand == nil)
            #expect(w.history.isEmpty, "nothing is replaced (A54)")
        }),
    FlatQueueScenario(
        number: "4d", setup: { w in w.playNow("A"); w.playNext("B2") }, before: "▶ A1 · B2 · A2 · A3 · A4",
        action: { $0.append("B") }, after: "▶ A1 · A2 · A3 · A4 · B2 · B3 · B1",
        check: { w in #expect(w.contents("B") == ["B1", "B2", "B3"]) }),
    FlatQueueScenario(
        number: "4e", setup: { w in a2(&w); w.addToPlaylist("A", "A5", atTop: false) }, before: "▶ A2 · A3 · A4",
        action: { $0.playNow("A") }, after: "▶ A2 · A3 · A4 · A5",
        check: { w in
            #expect(w.history.count == 1, "replacing, even with the same playlist, goes to the history")
            #expect(w.lastCommand == nil, "the running episode stays running; nothing to load")
        }),
    FlatQueueScenario(
        number: "5",
        setup: { w in a1X(&w); w.setPosition("A1", 750); w.playNow("B") }, before: "▶ B1 · B2 · B3",
        action: { $0.undo() }, after: "▶ A1 · X · A2 · A3 · A4",
        check: { w in
            #expect(w.position("A1") == 750)
            #expect(w.history.count == 2, "restoring is recorded too")
            #expect(w.history.snapshots.first?.reason == .restored)
            #expect(w.history.snapshots.first.map(w.render) == "▶ B1 · B2 · B3")
            #expect(w.lastCommand == w.playCommand("A1"))
        }),
    FlatQueueScenario(
        number: "6",
        setup: { w in
            w.playNow("A")
            w.setPosition("A1", 750)
            w.playNow("B")
            w.end()
        }, before: "▶ B2 · B3",
        action: { $0.playNow("A") }, after: "▶ A1 · A2 · A3 · A4",
        check: { w in
            #expect(w.position("A1") == 750, "A1 resumes at 12:30")
            #expect(w.history.count == 2)
            #expect(w.resume("B") == "B2", "B remembers where it was")
        }),
    FlatQueueScenario(
        number: "7", setup: { w in a1X(&w); w.append("B") }, before: "▶ A1 · X · A2 · A3 · A4 · B1 · B2 · B3",
        action: { $0.clear() }, after: "▶ A1",
        check: { w in
            #expect(w.history.count == 1)
            #expect(w.history.snapshots.first?.reason == .cleared)
            #expect(w.history.snapshots.first.map(w.render) == "▶ A1 · X · A2 · A3 · A4 · B1 · B2 · B3")
            #expect(w.contents("A") == ["A1", "A2", "A3", "A4"] && w.contents("B") == ["B1", "B2", "B3"], "playlists are unchanged")
            #expect(w.resume("A") == "A1", "A1 still runs")
            #expect(w.resume("B") == "B1", "B remembers B1 (N107)")
            #expect(w.lastCommand == nil, "the running episode plays on")
        }),
    FlatQueueScenario(
        number: "8", setup: { $0.playNow("A") }, before: "▶ A1 · A2 · A3 · A4",
        action: { $0.end() }, after: "▶ A2 · A3 · A4",
        check: { w in
            #expect(w.isPlayed("A1"))
            #expect(w.contents("A") == ["A2", "A3", "A4"], "the played policy removed A1")
            #expect(w.position("A1") == 0, "heard to the end → starts over next time")
            #expect(w.lastCommand == w.playCommand("A2"))
            #expect(w.resume("A") == "A2")
        }),
    FlatQueueScenario(
        number: "9", setup: a2, before: "▶ A2 · A3 · A4",
        action: { $0.skip() }, after: "▶ A3 · A4",
        check: { w in
            #expect(w.isPlayed("A2"), "⏭ counts as heard (N101)")
            #expect(w.contents("A") == ["A3", "A4"])
            #expect(w.position("A2") == 0)
            #expect(w.lastCommand == w.playCommand("A3"))
            #expect(w.history.isEmpty, "⏭ replaces nothing (A81)")
        }),
    FlatQueueScenario(
        number: "10", setup: { w in a2(&w); w.setPosition("A2", 310) }, before: "▶ A2 · A3 · A4",
        action: { $0.play("Z") }, after: "▶ Z · A2 · A3 · A4",
        check: { w in
            #expect(w.lastCommand == w.playCommand("Z"))
            #expect(w.position("A2") == 310, "A2 resumes at 5:10 afterwards")
            #expect(!w.isPlayed("A2"))
        }),
    FlatQueueScenario(
        number: "11", setup: { $0.playNow("B") }, before: "▶ B1 · B2 · B3",
        action: { $0.playNow("A", from: "A3") }, after: "▶ A3 · A4 · A1 · A2",
        check: { w in
            #expect(w.history.count == 1)
            #expect(w.lastCommand == w.playCommand("A3"))
            #expect(w.resume("B") == "B1")
        }),
    FlatQueueScenario(
        number: "12", setup: a2, before: "▶ A2 · A3 · A4",
        action: { $0.play("A4") }, after: "▶ A4 · A2 · A3",
        check: { w in
            #expect(w.lastCommand == w.playCommand("A4"))
            #expect(w.contents("A") == ["A2", "A3", "A4"], "A keeps its order")
        }),
    FlatQueueScenario(
        number: "13", setup: { _ in }, before: "–",
        action: { $0.playNow("K") }, after: "▶ K1 · K2 · K3",
        check: { w in
            #expect(w.lastCommand == w.playCommand("K1"), "a 'keep' playlist plays heard episodes, from the start (N1)")
            var w = w
            #expect(w.playthrough() == ["K2", "K3"])
            #expect(w.render() == "–")
            #expect(w.contents("K") == ["K1", "K2", "K3"], "'keep' keeps")
            #expect(w.resume("K") == nil, "played through once: the next start begins at the top (N107)")
        }),
    FlatQueueScenario(
        number: "13a", setup: { $0.playNow("K") }, before: "▶ K1 · K2 · K3",
        action: { $0.playNext("K3") }, after: "▶ K1 · K3 · K2"),
    FlatQueueScenario(
        number: "13b", setup: { w in w.play("K3"); w.end() }, before: "–",
        action: { $0.playNow("K") }, after: "▶ K1 · K2 · K3",
        check: { w in #expect(w.isPlayed("K3"), "K3 comes once more: 'keep' plays heard episodes (expected)") }),
    FlatQueueScenario(
        number: "14", setup: a2, before: "▶ A2 · A3 · A4",
        action: { w in
            w.addToPlaylist("A", "A5", atTop: false)
            w.addToPlaylist("A", "A0", atTop: true)
        }, after: "▶ A2 · A3 · A4",
        check: { w in
            #expect(w.live("A") == ["A2", "A3", "A4"])
            #expect(w.draft("A") == ["A0", "A5"], "new episodes wait in the draft, top or bottom (A86)")
            #expect(w.resume("A") == "A2")
        }),
    FlatQueueScenario(
        number: "15", setup: { $0.playNow("A") }, before: "▶ A1 · A2 · A3 · A4",
        action: { $0.moveItems(from: [1], to: 0) }, after: "▶ A1 · A3 · A2 · A4",
        check: { w in
            #expect(w.contents("A") == ["A1", "A2", "A3", "A4"], "dragging in Up Next changes no playlist")
            #expect(w.live("A") == ["A1", "A3", "A2", "A4"])
        }),
    FlatQueueScenario(
        number: "16", setup: a1X, before: "▶ A1 · X · A2 · A3 · A4",
        action: { $0.move("A4", behind: "A1") }, after: "▶ A1 · A4 · X · A2 · A3",
        check: { w in #expect(w.contents("A") == ["A1", "A2", "A3", "A4"], "dragging in the live part changes only Up Next (N106)") }),
    FlatQueueScenario(
        number: "17", setup: { $0.playNow("A") }, before: "▶ A1 · A2 · A3 · A4",
        action: { $0.remove("A3") }, after: "▶ A1 · A2 · A4",
        check: { w in
            #expect(w.live("A") == ["A1", "A2", "A4"])
            #expect(w.draft("A") == ["A3"], "swiped 'Aus der Warteschlange': back at its draft place")
            #expect(w.contents("A") == ["A1", "A2", "A3", "A4"], "A is unchanged")
        }),
    FlatQueueScenario(
        number: "18", setup: { $0.playNow("A") }, before: "▶ A1 · A2 · A3 · A4",
        action: { $0.removeFromPlaylist("A", "A3") }, after: "▶ A1 · A2 · A3 · A4",
        check: { w in
            #expect(w.contents("A") == ["A1", "A2", "A4"])
            #expect(w.live("A") == ["A1", "A2", "A4"], "A3 is no longer part of A's view, but still plays (A88)")
        }),
    FlatQueueScenario(
        number: "19", setup: { $0.playNow("B") }, before: "▶ B1 · B2 · B3",
        action: { $0.playNow("E") }, after: "▶ E1 · E2 · E3",
        check: { w in
            #expect(w.history.count == 1, "'Alles' is taken over like any playlist (A87)")
            var w = w
            w.addToPlaylist("E", "E0", atTop: true)
            #expect(w.render() == "▶ E1 · E2 · E3", "a new episode in 'Alles' no longer plays next (N98 is gone)")
        }),
]

@Test("Szenariotabelle §4.4 (v0.7)", arguments: flatScenarioTable)
func flatScenarioTable(_ scenario: FlatQueueScenario) {
    var world = UpNextWorld()
    scenario.setup(&world)
    #expect(world.render() == scenario.before, "Vorher")
    scenario.action(&world)
    #expect(world.render() == scenario.after, "Nachher")
    scenario.check(world)
}

// MARK: - Special cases below the table

struct FlatQueueSpecialCases {
    /// Concept §4.4: a playlist that holds the running episode is taken over behind it with
    /// *Nach der aktuellen Folge* and *Ans Ende* too; the episode keeps running (4e for the
    /// other two ways).
    @Test func appendingOrQueueingAfterCurrentThePlaylistOfTheRunningEpisodeKeepsItRunning() {
        var w = UpNextWorld()
        w.playNow("A")
        w.append("B")
        w.playNext("A3")
        #expect(w.render() == "▶ A1 · A3 · A2 · A4 · B1 · B2 · B3")
        w.append("A")
        #expect(w.render() == "▶ A1 · B1 · B2 · B3 · A2 · A3 · A4", "A goes on behind A1 at the end, in its order")
        #expect(w.lastCommand == nil, "A1 is not reloaded")
        w.playAfterCurrent("A")
        #expect(w.render() == "▶ A1 · A2 · A3 · A4 · B1 · B2 · B3")
        #expect(w.lastCommand == nil)
        #expect(w.history.isEmpty, "nothing is replaced")
    }

    // MARK: Every episode at most once (N105)

    @Test func anEpisodeSharedByTwoPlaylistsMovesWhenTheSecondIsTakenOver() {
        var w = UpNextWorld()
        w.playNow("A")
        w.append("S")  // S = A2, S1
        #expect(w.render() == "▶ A1 · A3 · A4 · A2 · S1", "A2 takes the place S gives it")
    }

    @Test func aSharedEpisodeHeardInTheMeantimeIsNotTakenOverAgain() {
        var w = UpNextWorld()
        w.playNow("A")
        w.end()
        w.end()  // A1, A2 played
        #expect(w.render() == "▶ A3 · A4")
        w.append("S")
        #expect(w.render() == "▶ A3 · A4 · S1")
    }

    @Test func playNextOnTheRunningEpisodeChangesNothing() {
        var w = UpNextWorld()
        w.playNow("A")
        w.playNext("A1")
        #expect(w.render() == "▶ A1 · A2 · A3 · A4")
        #expect(w.lastCommand == nil)
    }

    @Test func playNextOnAnEmptyUpNextCuesTheEpisode() {
        var w = UpNextWorld()
        w.playNext("X")
        #expect(w.render() == "▶ X")
        #expect(w.lastCommand == .cue(UpNextWorld.episode("X")), "cued, not playing (A22)")
    }

    @Test func playLastMovesAQueuedEpisodeToTheEnd() {
        var w = UpNextWorld()
        w.playNow("A")
        w.playLast("X")
        w.playLast("X")
        #expect(w.render() == "▶ A1 · A2 · A3 · A4 · X")
        w.playLast("A2")
        #expect(w.render() == "▶ A1 · A3 · A4 · X · A2", "'Am Ende' moves, also from the details (A91)")
    }

    @Test func playOnAQueuedEpisodeMovesItToTheFront() {
        var w = UpNextWorld()
        w.playNow("A")
        w.playLast("X")
        w.play("X")
        #expect(w.render() == "▶ X · A1 · A2 · A3 · A4", "the interrupted A1 comes back in front, X is not left behind")
    }

    @Test func anInterruptedEpisodeComesBackEvenIfItIsPlayed() {
        var w = UpNextWorld()
        w.playNow("K")  // K1 is played, a 'keep' playlist plays it anyway
        w.play("X")
        #expect(w.render() == "▶ X · K1 · K2 · K3", "one rule: the interrupted episode comes back in front")
    }

    @Test func takingOverAPlaylistWithNothingUnheardDoesNothing() {
        var w = UpNextWorld()
        w.playNow("A")
        _ = w.playthrough()
        #expect(w.render() == "–")
        w.playNow("B")
        w.playNow("A")
        #expect(w.render() == "▶ B1 · B2 · B3")
        #expect(w.history.isEmpty, "nothing was replaced")
        #expect(w.lastCommand == nil)
    }

    @Test func anEpisodeInNoPlaylistStaysInUpNext() {
        var w = UpNextWorld()
        w.playNow("A")
        w.removeFromPlaylist("A", "A3")
        w.deletePlaylist("A")
        #expect(w.render() == "▶ A1 · A2 · A3 · A4", "deleting the playlist leaves Up Next alone (A88)")
        #expect(w.playthrough() == ["A2", "A3", "A4"])
    }

    // MARK: Editing Up Next

    @Test func theRunningEpisodeSwipedAwayStaysUnplayed() {
        var w = UpNextWorld()
        w.playNow("A")
        w.setPosition("A1", 120)
        w.removeNowPlaying()
        #expect(w.render() == "▶ A2 · A3 · A4")
        #expect(!w.isPlayed("A1"))
        #expect(w.position("A1") == 120)
        #expect(w.contents("A") == ["A1", "A2", "A3", "A4"])
        #expect(w.lastCommand == w.playCommand("A2"))
        #expect(w.history.isEmpty)
    }

    @Test func theRunningEpisodeSwipedAwayWhilePausedCuesTheNext() {
        var w = UpNextWorld()
        w.playNow("A")
        w.removeNowPlaying(isPlaying: false)
        #expect(w.lastCommand == .cue(UpNextWorld.episode("A2")))
    }

    @Test func withdrawTakesBackPlayNext() {
        var w = UpNextWorld()
        w.playNow("A")
        w.playNext("X")
        w.withdraw("X")
        #expect(w.render() == "▶ A1 · A2 · A3 · A4")
    }

    @Test func movingBehindNilPutsTheEpisodeRightBehindTheRunningOne() {
        var w = UpNextWorld()
        w.playNow("A")
        w.playNext("X")
        w.move("A4", behind: nil)
        #expect(w.render() == "▶ A1 · A4 · X · A2 · A3")
    }

    @Test func skipWithoutANextEpisodeChangesNothing() {
        var w = UpNextWorld()
        w.play("X")
        #expect(w.episodeAfterSkip() == nil)
        w.skip()
        #expect(w.render() == "▶ X")
        #expect(!w.isPlayed("X"))
    }

    @Test func endingTheLastEpisodeStops() {
        var w = UpNextWorld()
        w.play("X")
        w.end()
        #expect(w.render() == "–")
        #expect(w.lastCommand == .stop)
    }

    // MARK: History

    @Test func theHistoryKeepsTheLastTwentyStates() {
        var w = UpNextWorld()
        for i in 0..<25 {
            w.playNow(i.isMultiple(of: 2) ? "A" : "B")
        }
        #expect(w.history.count == UpNextHistory.limit)
        #expect(w.history.snapshots.first.map(w.render) == "▶ B1 · B2 · B3", "newest first")
    }

    @Test func restoringAnOlderStateRecordsTheCurrentOne() {
        var w = UpNextWorld()
        w.playNow("A")
        w.playNow("B")
        w.playNow("K")
        let older = w.history.snapshots[1]  // ▶ A1 · A2 · A3 · A4
        w.restore(older)
        #expect(w.render() == "▶ A1 · A2 · A3 · A4")
        #expect(w.history.count == 3)
        #expect(w.history.snapshots.first?.reason == .restored)
        #expect(w.history.snapshots.first.map(w.render) == "▶ K1 · K2 · K3")
    }

    @Test func restoringIsLiteralAlsoForEpisodesPlayedMeanwhile() {
        // A state comes back as it was, played or not (positions and played status belong
        // to the episodes, A81).
        var w = UpNextWorld()
        w.playNow("A")
        w.playNow("B")
        w.end()  // B1 played
        w.undo()
        #expect(w.render() == "▶ A1 · A2 · A3 · A4")
    }

    // MARK: Resume point (N107)

    @Test func theResumePointIsTheFrontmostQueuedEpisodeWhileThePlaylistIsQueued() {
        var w = UpNextWorld()
        w.playNow("A")
        #expect(w.resume("A") == "A1")
        w.moveItems(from: [2], to: 0)  // A4 before A2
        #expect(w.resume("A") == "A1", "the running episode counts")
        w.end()
        #expect(w.resume("A") == "A4")
        w.playNext("B2")
        #expect(w.resume("B") == "B2", "queued through 'Als Nächstes' is enough")
    }

    @Test func aPlaylistWhoseEpisodesLeaveUnplayedRemembersTheFrontmost() {
        var w = UpNextWorld()
        w.playNow("A")
        w.remove("A2")
        w.remove("A3")
        w.remove("A4")
        #expect(w.render() == "▶ A1")
        w.removeNowPlaying()
        #expect(w.render() == "–")
        #expect(w.resume("A") == "A1", "'Weiter bei: A1'")
        w.playNow("A")
        #expect(w.render() == "▶ A1 · A2 · A3 · A4", "the next start begins there")
    }

    @Test func skippingTheLastQueuedEpisodeOfAPlaylistLeavesNoResumePoint() {
        var w = UpNextWorld()
        w.playNow("K")
        w.remove("K2")
        w.remove("K3")
        w.playLast("X")
        w.skip()  // K1 skipped: heard on purpose
        #expect(w.render() == "▶ X")
        #expect(w.resume("K") == nil, "skipped counts like ended (N107)")
    }

    @Test func aPlaylistPlayedThroughForgetsItsResumePoint() {
        var w = UpNextWorld()
        w.playNow("A")
        _ = w.playthrough()
        #expect(w.resume("A") == nil)
        w.playNow("K")
        _ = w.playthrough()
        #expect(w.resume("K") == nil, "also a 'keep' playlist, after one pass")
    }

    /// A stored resume point survives single episodes that pass through Up Next; a takeover
    /// clears it, and an ended episode clears it only if it was that point.
    @Test func singleEpisodesPassingThroughLeaveAStoredResumePointAlone() {
        var w = UpNextWorld()
        w.playNow("K")
        w.playNow("B")
        #expect(w.resume("K") == "K1", "stored when B replaced K")
        w.playNext("K3")
        w.end()
        #expect(w.render() == "▶ K3 · B2 · B3")
        w.end()
        #expect(w.resume("K") == "K1", "K3 ended, but K1 is the stored point")
        w.playNext("K2")
        w.remove("K2")
        #expect(w.resume("K") == "K1", "K2 swiped away: nothing overwrites a stored point")
        w.playNext("K1")
        w.end()
        #expect(w.render() == "▶ K1 · B3")
        w.end()
        #expect(w.resume("K") == nil, "the stored point itself ended")
        w.playNow("K")
        #expect(w.render() == "▶ K1 · K2 · K3", "a keep playlist from the top, played episodes included")
        w.playNow("B")
        #expect(w.resume("K") == "K1")
        w.playNow("K")
        w.playNow("B")
        #expect(w.resume("K") == "K1", "taken over (stored cleared), then replaced: the frontmost")
    }

    @Test func aResumePointWhoseEpisodeLeftThePlaylistIsEmpty() {
        var w = UpNextWorld()
        w.playNow("K")
        w.playNow("B")
        #expect(w.resume("K") == "K1")
        w.removeFromPlaylist("K", "K1")
        #expect(w.resume("K") == nil, "N13 is gone: the next start begins at the top")
        w.playNow("K")
        #expect(w.render() == "▶ K2 · K3")
    }

    @Test func replacingWithTheSameRunningPlaylistKeepsTheRunningEpisode() {
        var w = UpNextWorld()
        w.playNow("A")
        w.end()
        w.setPosition("A2", 500)
        w.playNow("A")
        #expect(w.render() == "▶ A2 · A3 · A4")
        #expect(w.position("A2") == 500)
        #expect(w.lastCommand == nil, "nothing to reload")
    }

    @Test func takingOverAQueuedPlaylistStartsAtItsFrontmostQueuedEpisode() {
        var w = UpNextWorld()
        w.playNow("B")
        w.playNext("A2")
        w.playNext("A3")
        #expect(w.render() == "▶ B1 · A3 · A2 · B2 · B3")
        #expect(w.resume("A") == "A3")
        w.playNow("A")
        #expect(w.render() == "▶ A3 · A4 · A1 · A2", "the resume point is the frontmost queued episode, not a stored one (N107)")
    }

    @Test func startingFromAnEpisodeMakesItTheFirstOfTheTakeover() {
        var w = UpNextWorld()
        w.playNow("A")
        w.playAfterCurrent("B", from: "B3")
        #expect(w.render() == "▶ A1 · B3 · B1 · B2 · A2 · A3 · A4", "'Playlist ab hier' in a 'remove' playlist goes round once")
        w.append("K", from: "K2")
        #expect(w.render() == "▶ A1 · B3 · B1 · B2 · A2 · A3 · A4 · K2 · K3", "a 'keep' playlist does not go round")
    }

    // MARK: The playlist view's split (N106)

    @Test func theLivePartShowsEpisodesQueuedThroughAnotherPlaylist() {
        var w = UpNextWorld()
        w.playNow("A")
        #expect(w.live("S") == ["A2"], "A2 is queued through A and shows on top of S")
        #expect(w.draft("S") == ["S1"])
        w.playNext("S1")
        #expect(w.live("S") == ["S1", "A2"], "what is far up in Up Next is far up in every playlist")
    }

    @Test func theLivePartIsEmptyForAPlaylistThatIsNotQueued() {
        var w = UpNextWorld()
        w.playNow("A")
        #expect(w.live("B").isEmpty)
        #expect(w.draft("B") == ["B1", "B2", "B3"])
    }

    @Test func thePlayedPolicyNeverRemovesTheRunningEpisode() {
        var w = UpNextWorld()
        w.playNow("A")
        w.markPlayedWhileRunning()
        #expect(w.contents("A") == ["A1", "A2", "A3", "A4"], "A1 stays while it is in the player")
        w.end()
        #expect(w.contents("A") == ["A2", "A3", "A4"])
    }
}

// MARK: - Test world: a minimal stand-in for UpNextService (v0.7)

/// Holds the persistent state (Up Next, playlists, stored resume points, played flags,
/// positions, history), builds a fresh `QueueResolver` for every operation like the
/// service will, keeps the resume points the way the store will (N107: one before/after
/// comparison per operation) and applies the played policy after an episode ended.
struct UpNextWorld {
    private(set) var state = UpNextState()
    private(set) var history = UpNextHistory()
    private var playlists: [String: QueuePlaylist] = [:]
    /// `Playlist.resumeEpisode` as stored (N107); "Läuft" / "Als Nächstes" are derived.
    private var storedResume: [String: EpisodeID] = [:]
    private var played: Set<String> = []
    private var positions: [String: TimeInterval] = [:]
    var lastCommand: PlaybackCommand?
    private var now = Date(timeIntervalSinceReferenceDate: 0)

    /// A, B: "remove" playlists A1–A4, B1–B3. K: "keep" playlist K1–K3, K1 already played.
    /// S: "remove" playlist that shares A2 with A, plus S1. E: stands in for "Alles" (E1–E3).
    init() {
        let defs: [(String, PlayedPolicy, [String])] = [
            ("A", .remove, ["A1", "A2", "A3", "A4"]),
            ("B", .remove, ["B1", "B2", "B3"]),
            ("K", .keep, ["K1", "K2", "K3"]),
            ("S", .remove, ["A2", "S1"]),
            ("E", .remove, ["E1", "E2", "E3"]),
        ]
        for (name, policy, episodes) in defs {
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

    /// "Ersetzen" / "Playlist ab hier" (takes the playlist over, N104).
    mutating func playNow(_ playlist: String, from episode: String? = nil) {
        run { r, h, now in r.playNow(playlist: Self.playlist(playlist), startingAt: episode.map(Self.episode), history: &h, now: now) }
    }

    /// "Ans Ende".
    mutating func append(_ playlist: String, from episode: String? = nil) {
        run { r, _, _ in r.append(playlist: Self.playlist(playlist), startingAt: episode.map(Self.episode)) }
    }

    /// "Nach der aktuellen Folge" (scenario 4c).
    mutating func playAfterCurrent(_ playlist: String, from episode: String? = nil) {
        run { r, _, _ in r.playAfterCurrent(playlist: Self.playlist(playlist), startingAt: episode.map(Self.episode)) }
    }

    /// "Als Nächstes" (moves, N105).
    mutating func playNext(_ episode: String) {
        run { r, _, _ in r.playNext(Self.episode(episode)) }
    }

    /// "Am Ende" (moves, N105).
    mutating func playLast(_ episode: String) {
        run { r, _, _ in r.playLast(Self.episode(episode)) }
    }

    /// "▶ Abspielen".
    mutating func play(_ episode: String) {
        run { r, _, _ in r.play(Self.episode(episode)) }
    }

    /// Takes back "Als Nächstes" / "Am Ende" (undo).
    mutating func withdraw(_ episode: String, isPlaying: Bool = true) {
        run { r, _, _ in r.withdraw(Self.episode(episode), isPlaying: isPlaying) }
    }

    /// A waiting episode swiped away in Up Next, or dragged from the live part into the
    /// draft (N108; the draft position is the PlaylistService's job).
    mutating func remove(_ episode: String) {
        run { r, _, _ in r.remove(Self.episode(episode)); return nil }
    }

    /// The running episode swiped away in Up Next.
    mutating func removeNowPlaying(isPlaying: Bool = true) {
        run { r, _, _ in r.removeNowPlaying(isPlaying: isPlaying) }
    }

    /// Dragging in Up Next (offsets in `state.items`, SwiftUI `onMove`).
    mutating func moveItems(from offsets: IndexSet, to destination: Int) {
        run { r, _, _ in r.moveItems(fromOffsets: offsets, toOffset: destination); return nil }
    }

    /// Dragging in the live part of a playlist view, or from the draft into it (N106, N108):
    /// the episode goes right behind `predecessor` (nil = right behind the running episode).
    mutating func move(_ episode: String, behind predecessor: String?) {
        run { r, _, _ in r.move(Self.episode(episode), behind: predecessor.map(Self.episode)); return nil }
    }

    mutating func clear() {
        run { r, h, now in r.clear(history: &h, now: now); return nil }
    }

    mutating func undo() {
        guard let latest = history.snapshots.first else { return }
        restore(latest)
    }

    mutating func restore(_ snapshot: UpNextSnapshotValue) {
        run { r, h, now in r.restore(snapshot, history: &h, now: now) }
    }

    /// The running episode reached its end: the next one plays, then the ended one is
    /// marked played and the played policy applies (concept §4.4, "Folge E endet").
    mutating func end() {
        guard let ended = state.nowPlaying else { return }
        let name = Self.name(ended.uuid)
        run(endsEpisode: true) { r, _, _ in r.episodeEnded() }
        played.insert(name)
        positions[name] = 0  // heard to the end → starts over next time
        applyPlayedPolicy()
    }

    /// ⏭ (N101): like the end of the episode, if something follows.
    mutating func skip(isPlaying: Bool = true) {
        guard let skipped = state.nowPlaying else { return }
        let name = Self.name(skipped.uuid)
        run(endsEpisode: true) { r, _, _ in r.skip(isPlaying: isPlaying) }
        guard state.nowPlaying != skipped else { return }
        played.insert(name)
        positions[name] = 0
        applyPlayedPolicy()
    }

    /// The episode ⏭ would play now.
    func episodeAfterSkip() -> String? {
        resolver().episodeAfterSkip().map { Self.name($0.uuid) }
    }

    /// Near-end threshold reached or marked played by hand while the episode runs.
    mutating func markPlayedWhileRunning() {
        guard let running = state.nowPlaying else { return }
        played.insert(Self.name(running.uuid))
        applyPlayedPolicy()
    }

    /// Ends episodes until playback stops; returns the episodes that played after the current one.
    mutating func playthrough() -> [String] {
        var names: [String] = []
        while state.nowPlaying != nil {
            end()
            if let next = state.nowPlaying { names.append(Self.name(next.uuid)) }
        }
        return names
    }

    // MARK: Playlist content and episode state (changed by other services; Up Next is not told)

    mutating func addToPlaylist(_ playlist: String, _ episode: String, atTop: Bool) {
        if atTop {
            playlists[playlist]?.episodes.insert(Self.episode(episode), at: 0)
        } else {
            playlists[playlist]?.episodes.append(Self.episode(episode))
        }
    }

    /// Removed by hand (A88): the playlist changes, Up Next does not. A resume point that
    /// left the playlist is empty (N107; the store derives that when it reads).
    mutating func removeFromPlaylist(_ playlist: String, _ episode: String) {
        let id = Self.episode(episode)
        playlists[playlist]?.episodes.removeAll { $0 == id }
        if storedResume[playlist] == id { storedResume[playlist] = nil }
    }

    mutating func deletePlaylist(_ playlist: String) {
        playlists[playlist] = nil
        storedResume[playlist] = nil
    }

    mutating func setPosition(_ episode: String, _ seconds: TimeInterval) { positions[episode] = seconds }

    /// The service's played policy: removes played episodes from "remove" playlists,
    /// except the running one (PlayedRules). Up Next is not involved any more.
    private mutating func applyPlayedPolicy() {
        for name in played.sorted() {
            let id = Self.episode(name)
            let containing = playlists.values.filter { $0.episodes.contains(id) }
                .map { PlaylistPolicy(playlistID: $0.id, policy: $0.playedPolicy) }
            let remove = PlayedRules.playlistsToRemoveFrom(containing, isNowPlaying: state.nowPlaying == id)
            for (key, playlist) in playlists where remove.contains(playlist.id) {
                playlists[key]?.episodes.removeAll { $0 == id }
                if storedResume[key] == id { storedResume[key] = nil }
            }
        }
    }

    // MARK: Reading

    func render() -> String { render(state) }

    func render(_ snapshot: UpNextSnapshotValue) -> String { render(snapshot.state) }

    func render(_ state: UpNextState) -> String {
        var parts: [String] = []
        if let now = state.nowPlaying { parts.append("▶ " + Self.name(now.uuid)) }
        parts += state.items.map { Self.name($0.uuid) }
        return parts.isEmpty ? "–" : parts.joined(separator: " · ")
    }

    /// The playlist's resume point as the service reads it (N107): its frontmost episode in
    /// Up Next, otherwise the stored one.
    func resume(_ playlist: String) -> String? {
        (resolver().nextQueuedEpisode(of: Self.playlist(playlist)) ?? storedResume[playlist]).map { Self.name($0.uuid) }
    }

    /// The two parts of the playlist view (N106).
    func live(_ playlist: String) -> [String] { resolver().split(of: Self.playlist(playlist)).live.map { Self.name($0.uuid) } }
    func draft(_ playlist: String) -> [String] { resolver().split(of: Self.playlist(playlist)).draft.map { Self.name($0.uuid) } }

    func contents(_ playlist: String) -> [String] {
        playlists[playlist]?.episodes.map { Self.name($0.uuid) } ?? []
    }

    func isPlayed(_ episode: String) -> Bool { played.contains(episode) }
    func position(_ episode: String) -> TimeInterval { positions[episode] ?? 0 }

    func playCommand(_ episode: String) -> PlaybackCommand {
        .play(Self.episode(episode))
    }

    // MARK: Plumbing

    private func resolver() -> QueueResolver {
        QueueResolver(
            state: state,
            playlists: playlists.map { name, playlist in
                QueuePlaylist(id: playlist.id, playedPolicy: playlist.playedPolicy, episodes: playlist.episodes, resumeEpisode: storedResume[name])
            },
            playedEpisodes: Set(played.map(Self.episode)))
    }

    /// One operation, as `UpNextService.perform` will run it. `endsEpisode`: the running
    /// episode ends or is skipped (N107, see `UpNextStore.write`).
    private mutating func run(endsEpisode: Bool = false, _ operation: (inout QueueResolver, inout UpNextHistory, Date) -> PlaybackCommand?) {
        now += 60
        var resolver = resolver()
        let before = Dictionary(uniqueKeysWithValues: playlists.map { ($0.key, resolver.nextQueuedEpisode(of: $0.value.id)) })
        let snapshot = resolver.playlists
        lastCommand = operation(&resolver, &history, now)
        state = resolver.state
        // Invariants of the flat queue (N104, N105).
        #expect(Set(state.items).count == state.items.count, "no episode twice in Up Next")
        #expect(state.nowPlaying.map { !state.items.contains($0) } ?? true, "the running episode is not waiting too")
        #expect(resolver.playlists == snapshot, "Up Next never changes a playlist, not even its order or resume point (N104, N107)")
        // The store's part of N107: a taken-over playlist forgets its stored point; one that
        // dropped out of Up Next stores its frontmost episode unless it has one, and an ended
        // or skipped episode clears the stored point only if it was that point.
        for name in playlists.keys where resolver.takenOverPlaylists.contains(playlists[name]!.id) {
            storedResume[name] = nil
        }
        for (name, frontmost) in before {
            guard let frontmost, resolver.nextQueuedEpisode(of: playlists[name]!.id) == nil,
                  !resolver.takenOverPlaylists.contains(playlists[name]!.id) else { continue }
            if endsEpisode {
                if storedResume[name] == frontmost { storedResume[name] = nil }
            } else if storedResume[name] == nil {
                storedResume[name] = frontmost
            }
        }
    }
}
