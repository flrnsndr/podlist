import Foundation
import Testing
@testable import PodlistKit

/// The player sheet snaps between the player and the show notes below it (N80): a drag is
/// strongly damped, short of 30 % of the way it springs back, past it (or with a flick, whose
/// momentum is projected) it snaps; inside the notes, scrolling is free.
struct PlayerPageSnapTests {
    private let notesTop = 800.0

    @Test(arguments: [
        (projected: 0.0, expected: 0.0),
        (projected: 100, expected: 0),  // a short drag springs back to the player
        (projected: 239, expected: 0),
        (projected: 241, expected: 800),  // past 30 % of the way, it snaps to the notes
        (projected: 790, expected: 800),
        (projected: 2_400, expected: 800),  // a hard flick stops at the start of the notes
        (projected: -50, expected: 0),
    ])
    func fromThePlayer(projected: Double, expected: Double) {
        #expect(PlayerPageSnap.target(projected: projected, start: 0, notesTop: notesTop) == expected)
    }

    @Test(arguments: [
        (projected: 800.0, expected: 800.0),
        (projected: 700, expected: 800),  // a short drag up springs back to the notes
        (projected: 561, expected: 800),
        (projected: 559, expected: 0),  // past 30 % of the way up, it snaps to the player
        (projected: -300, expected: 0),
        (projected: 1_500, expected: 1_500),  // reading on: free
    ])
    func fromTheStartOfTheNotes(projected: Double, expected: Double) {
        #expect(PlayerPageSnap.target(projected: projected, start: notesTop, notesTop: notesTop) == expected)
    }

    /// Deep in the notes, a flick up stops at their start; one more swipe goes to the player.
    @Test(arguments: [-500.0, 0, 400, 799])
    func fromDeepInTheNotesTheirStartCatches(projected: Double) {
        #expect(PlayerPageSnap.target(projected: projected, start: 3_000, notesTop: notesTop) == notesTop)
    }

    @Test func freeInsideTheNotes() {
        #expect(PlayerPageSnap.target(projected: 2_000, start: 3_000, notesTop: notesTop) == 2_000)
    }

    /// Without notes there is nothing to snap to.
    @Test func withoutNotesNothingChanges() {
        #expect(PlayerPageSnap.target(projected: 30, start: 0, notesTop: 0) == 30)
        #expect(!PlayerPageSnap.isBetweenPages(start: 0, notesTop: 0))
        #expect(!PlayerPageSnap.isArmed(offset: 500, start: 0, notesTop: 0))
    }

    /// A drag counts from where the finger lands, also while the last snap still bounces: the
    /// rubber bands beyond both ends count as that end (short notes end at `notesTop`).
    @Test(arguments: [
        (offset: -22.0, maxOffset: 800.0, expected: 0.0),
        (offset: 0, maxOffset: 800, expected: 0),
        (offset: 300, maxOffset: 800, expected: 300),  // a snap still on its way
        (offset: 866, maxOffset: 800, expected: 800),  // bouncing at the end of short notes
        (offset: 2_000, maxOffset: 3_000, expected: 2_000),  // reading long notes
    ])
    func dragStart(offset: Double, maxOffset: Double, expected: Double) {
        #expect(PlayerPageSnap.start(offset: offset, maxOffset: maxOffset) == expected)
    }

    /// Catching the bounce after a snap to short notes and flicking up goes to the player; it is
    /// not a flick from deep in the notes.
    @Test func aFlickUpWhileShortNotesBounceGoesToThePlayer() {
        let start = PlayerPageSnap.start(offset: 866, maxOffset: notesTop)
        #expect(PlayerPageSnap.isBetweenPages(start: start, notesTop: notesTop))
        #expect(PlayerPageSnap.target(projected: 300, start: start, notesTop: notesTop) == 0)
    }

    @Test(arguments: [(start: 0.0, between: true), (300, true), (800, true), (801, true), (802, false), (3_000, false)])
    func dragsBetweenThePages(start: Double, between: Bool) {
        #expect(PlayerPageSnap.isBetweenPages(start: start, notesTop: notesTop) == between)
    }

    /// Only the way between the pages counts, from where the drag began (so the content does
    /// not jump when a drag catches a snap on its way).
    @Test(arguments: [
        (offset: 300.0, start: 0.0, expected: 300.0),
        (offset: -30, start: 0, expected: 0),  // above the player: the system's rubber band
        (offset: 500, start: 800, expected: -300),
        (offset: 900, start: 800, expected: 0),  // into the notes: free
        (offset: 700, start: 700, expected: 0),  // caught a snap on its way
        (offset: 650, start: 700, expected: -50),
        (offset: 900, start: 700, expected: 100),
    ])
    func distanceBetweenThePages(offset: Double, start: Double, expected: Double) {
        #expect(PlayerPageSnap.distance(offset: offset, start: start, notesTop: notesTop) == expected)
    }

    /// Armed when letting go there would land on the other page than letting go where the drag
    /// began, so the haptic tick matches the snap.
    @Test(arguments: [
        (offset: 239.0, start: 0.0, armed: false),
        (241, 0, true),
        (561, 800, false),
        (559, 800, true),
        (900, 800, false),  // reading on
        (600, 700, false),  // caught on its way to the notes: there unless pulled back
        (550, 700, true),
        (250, 300, false),
        (230, 300, true),
    ])
    func armedWhereTheSnapChanges(offset: Double, start: Double, armed: Bool) {
        #expect(PlayerPageSnap.isArmed(offset: offset, start: start, notesTop: notesTop) == armed)
    }

    /// The content lags far behind the finger: at the threshold it has moved about a third.
    @Test func dragsAreStronglyDamped() {
        #expect(PlayerPageSnap.resisted(0, pageHeight: notesTop) == 0)
        let atThreshold = PlayerPageSnap.resisted(240, pageHeight: notesTop)
        #expect(atThreshold > 60 && atThreshold < 100)
        #expect(PlayerPageSnap.resisted(-240, pageHeight: notesTop) == -atThreshold)
        #expect(PlayerPageSnap.resisted(480, pageHeight: notesTop) > atThreshold)
        #expect(PlayerPageSnap.resisted(100_000, pageHeight: notesTop) < notesTop)
    }
}
