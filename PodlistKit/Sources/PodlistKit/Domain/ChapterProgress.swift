import Foundation

/// The player's progress bar with chapters as segments (concept §4.6): one segment per visible
/// chapter, as wide as the chapter is long, with a small gap between them. The first segment
/// starts at 0, so time before the first chapter counts towards it; without chapters there is
/// one segment. Also maps between a point of the bar and a time, for scrubbing.
public struct ChapterProgress: Equatable, Sendable {
    public struct Segment: Hashable, Sendable {
        public var start: TimeInterval
        public var end: TimeInterval
        public var length: TimeInterval { end - start }

        public init(start: TimeInterval, end: TimeInterval) {
            self.start = start
            self.end = end
        }
    }

    /// Where a segment sits in a bar, in points from its leading edge.
    public struct Frame: Hashable, Sendable {
        public var x: Double
        public var width: Double
    }

    /// Never shorter than the start of the last chapter.
    public let duration: TimeInterval
    public let segments: [Segment]

    /// `chapters` as normalized (`ChapterSelection.normalized`); hidden ones get no segment.
    public init(chapters: [Chapter], duration: TimeInterval) {
        let starts = ChapterSelection.visible(chapters).map(\.start).dropFirst()
        let duration = max(duration, starts.last ?? 0, 0)
        let bounds = [0] + starts + [duration]
        self.duration = duration
        segments = zip(bounds, bounds.dropFirst()).map { Segment(start: $0, end: $1) }
    }

    /// The segment that plays at `time`.
    public func index(at time: TimeInterval) -> Int {
        segments.lastIndex { $0.start <= time } ?? 0
    }

    /// Time left in the segment that plays at `time`.
    public func remaining(at time: TimeInterval) -> TimeInterval {
        max(0, segments[index(at: time)].end - max(time, 0))
    }

    /// The played share of segment `index` at `time`, 0...1.
    public func played(_ index: Int, at time: TimeInterval) -> Double {
        let segment = segments[index]
        guard segment.length > 0 else { return time > segment.end ? 1 : 0 }
        return min(max((time - segment.start) / segment.length, 0), 1)
    }

    /// The segments in a bar `width` points wide with `gap` points between them. Gaps shrink so
    /// they never take more than a fifth of the bar.
    public func frames(width: Double, gap: Double) -> [Frame] {
        let gap = effectiveGap(gap, width: width)
        let available = max(0, width - gap * Double(segments.count - 1))
        var x = 0.0
        return segments.map { segment in
            let share = duration > 0 ? segment.length / duration : 1 / Double(segments.count)
            defer { x += available * share + gap }
            return Frame(x: x, width: available * share)
        }
    }

    /// The time at `x` points from the leading edge of the bar; half a gap belongs to each of
    /// its neighbours.
    public func time(atX x: Double, width: Double, gap: Double) -> TimeInterval {
        let gap = effectiveGap(gap, width: width)
        for (segment, frame) in zip(segments, frames(width: width, gap: gap)) {
            guard x < frame.x + frame.width + gap / 2 || segment == segments.last else { continue }
            guard frame.width > 0 else { return segment.start }
            return segment.start + min(max((x - frame.x) / frame.width, 0), 1) * segment.length
        }
        return 0
    }

    private func effectiveGap(_ gap: Double, width: Double) -> Double {
        guard segments.count > 1 else { return 0 }
        return min(gap, width / 5 / Double(segments.count - 1))
    }
}
