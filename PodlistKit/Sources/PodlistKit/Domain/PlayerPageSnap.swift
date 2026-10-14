import Foundation

/// How the player sheet moves between the player and the show notes below it (N80).
///
/// Offsets are measured from the top of the player (0); the notes start at `notesTop`. While
/// dragging from one to the other, the content follows the finger only reluctantly
/// (`resisted`, a rubber band), so it feels sticky. On release, the projected offset decides
/// (where the scroll would stop on its own, so a flick counts with its momentum, WWDC18
/// "Designing Fluid Interfaces"): short of `threshold` of the way it springs back, past it it
/// snaps. Inside the notes, scrolling is free. A drag may begin anywhere between the pages, also
/// while the last snap is still moving or bouncing; it counts from where the finger landed.
public enum PlayerPageSnap {
    /// Share of the distance between player and notes a drag must reach to switch.
    public static let threshold = 0.3
    /// How strongly a drag between the pages is damped (UIKit's rubber band uses 0.55).
    public static let resistance = 0.35

    public static func target(projected: Double, start: Double, notesTop: Double) -> Double {
        guard notesTop > 0 else { return projected }
        if start < notesTop / 2 {
            return projected > notesTop * threshold ? notesTop : 0
        }
        if projected >= notesTop { return projected }
        // Deep in the notes, their start catches a flick up; one more swipe goes to the player.
        if !isBetweenPages(start: start, notesTop: notesTop) { return notesTop }
        return projected < notesTop * (1 - threshold) ? 0 : notesTop
    }

    /// How far the content moves for a drag of `distance` points between the pages: always
    /// less than the finger, less and less the further it goes, never beyond `pageHeight`.
    public static func resisted(_ distance: Double, pageHeight: Double) -> Double {
        guard pageHeight > 0 else { return distance }
        let magnitude = (1 - 1 / (abs(distance) * resistance / pageHeight + 1)) * pageHeight
        return distance < 0 ? -magnitude : magnitude
    }

    /// Where a drag counts from: the scroll offset when the finger lands. The rubber bands beyond
    /// both ends count as that end, so catching the bounce after a snap starts on that page
    /// (short notes end right at `notesTop`).
    public static func start(offset: Double, maxOffset: Double) -> Double {
        min(max(offset, 0), max(maxOffset, 0))
    }

    /// Whether a drag from `start` moves between the pages (damped, armed, snapping); deeper in
    /// the notes it scrolls freely.
    public static func isBetweenPages(start: Double, notesTop: Double) -> Bool {
        notesTop > 0 && start <= notesTop + 1
    }

    /// How far a drag from `start` has moved between the pages; beyond them (into the notes,
    /// above the player) it does not count.
    public static func distance(offset: Double, start: Double, notesTop: Double) -> Double {
        min(max(offset, 0), notesTop) - min(max(start, 0), notesTop)
    }

    /// Whether letting go at `offset` would land on the other page than letting go where the
    /// drag began, so the haptic tick matches the snap.
    public static func isArmed(offset: Double, start: Double, notesTop: Double) -> Bool {
        guard isBetweenPages(start: start, notesTop: notesTop) else { return false }
        func landsOnNotes(_ projected: Double) -> Bool {
            target(projected: projected, start: start, notesTop: notesTop) >= notesTop
        }
        return landsOnNotes(offset) != landsOnNotes(start)
    }
}
