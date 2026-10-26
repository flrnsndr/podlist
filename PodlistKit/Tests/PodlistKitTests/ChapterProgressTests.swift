import Foundation
import Testing
@testable import PodlistKit

/// The player's progress bar with one segment per chapter (concept §4.6): where segments start
/// and end, which one is current, how much is left in it, and the mapping between the bar's
/// width and time for scrubbing.
struct ChapterProgressTests {
    private let chapters = [
        Chapter(start: 0, end: 300, title: "Intro"),
        Chapter(start: 300, end: 1_800, title: "Thema eins"),
        Chapter(start: 1_800, end: 3_600, title: "Thema zwei"),
    ]

    private func segment(_ start: TimeInterval, _ end: TimeInterval) -> ChapterProgress.Segment {
        ChapterProgress.Segment(start: start, end: end)
    }

    @Test func oneSegmentPerVisibleChapter() {
        var chapters = chapters
        chapters.insert(Chapter(start: 600, end: 700, title: "Bild", isHidden: true), at: 2)
        let progress = ChapterProgress(chapters: chapters, duration: 3_600)
        #expect(progress.segments == [segment(0, 300), segment(300, 1_800), segment(1_800, 3_600)])
    }

    @Test func withoutChaptersOneSegment() {
        #expect(ChapterProgress(chapters: [], duration: 1_200).segments == [segment(0, 1_200)])
        let onlyHidden = [Chapter(start: 0, title: "Bild", isHidden: true)]
        #expect(ChapterProgress(chapters: onlyHidden, duration: 1_200).segments == [segment(0, 1_200)])
    }

    /// Time before the first chapter belongs to its segment; the bar always starts at 0.
    @Test func theFirstSegmentStartsAtZero() {
        let late = [Chapter(start: 60, title: "Eins"), Chapter(start: 600, title: "Zwei")]
        let progress = ChapterProgress(chapters: late, duration: 1_200)
        #expect(progress.segments == [segment(0, 600), segment(600, 1_200)])
        #expect(progress.index(at: 10) == 0)
    }

    /// Without a known duration the last chapter still has a segment (of length 0).
    @Test func aChapterBeyondTheDurationStillCounts() {
        let progress = ChapterProgress(chapters: chapters, duration: 1)
        #expect(progress.duration == 1_800)
        #expect(progress.segments.last == segment(1_800, 1_800))
    }

    @Test(arguments: [
        (time: 0.0, index: 0, remaining: 300.0),
        (time: 299, index: 0, remaining: 1),
        (time: 300, index: 1, remaining: 1_500),
        (time: 3_000, index: 2, remaining: 600),
        (time: 4_000, index: 2, remaining: 0),
        (time: -5, index: 0, remaining: 300),
    ])
    func currentSegmentAndTimeLeft(time: TimeInterval, index: Int, remaining: TimeInterval) {
        let progress = ChapterProgress(chapters: chapters, duration: 3_600)
        #expect(progress.index(at: time) == index)
        #expect(progress.remaining(at: time) == remaining)
    }

    @Test(arguments: [
        (index: 0, time: 1_000.0, played: 1.0),
        (index: 1, time: 1_050, played: 0.5),
        (index: 2, time: 1_050, played: 0),
        (index: 2, time: 3_600, played: 1),
    ])
    func playedShareOfASegment(index: Int, time: TimeInterval, played: Double) {
        #expect(ChapterProgress(chapters: chapters, duration: 3_600).played(index, at: time) == played)
    }

    /// Segments share the width minus the gaps, in proportion to their length.
    @Test func framesFillTheWidth() {
        let progress = ChapterProgress(chapters: chapters, duration: 3_600)
        let frames = progress.frames(width: 364, gap: 2)
        #expect(frames.map(\.x) == [0, 32, 184])
        #expect(frames.map(\.width) == [30, 150, 180])
        #expect(frames.last.map { $0.x + $0.width } == 364)
    }

    /// Many short chapters: the gaps shrink so they never take more than a fifth of the bar.
    @Test func gapsShrinkWithManyChapters() {
        let many = (0..<100).map { Chapter(start: TimeInterval($0 * 60), title: "\($0)") }
        let progress = ChapterProgress(chapters: many, duration: 6_000)
        let frames = progress.frames(width: 300, gap: 2)
        let gaps = zip(frames, frames.dropFirst()).map { $1.x - ($0.x + $0.width) }
        #expect(gaps.allSatisfy { abs($0 - 60.0 / 99) < 0.0001 })
        #expect(abs(frames.map(\.width).reduce(0, +) - 240) < 0.0001)
    }

    @Test(arguments: [
        (x: 0.0, time: 0.0),
        (x: -20, time: 0),
        (x: 15, time: 150),  // halfway through the first segment
        (x: 30.9, time: 300),  // in the gap: the end of the segment before it
        (x: 31.1, time: 300),  // in the gap: the start of the segment after it
        (x: 107, time: 1_050),
        (x: 364, time: 3_600),
        (x: 500, time: 3_600),
    ])
    func timeAtAPointOfTheBar(x: Double, time: TimeInterval) {
        let progress = ChapterProgress(chapters: chapters, duration: 3_600)
        #expect(abs(progress.time(atX: x, width: 364, gap: 2) - time) < 0.0001)
    }

    @Test func anEmptyBarMapsToZero() {
        let progress = ChapterProgress(chapters: [], duration: 0)
        #expect(progress.time(atX: 10, width: 300, gap: 2) == 0)
        #expect(progress.frames(width: 300, gap: 2).map(\.width) == [300])
        #expect(progress.played(0, at: 0) == 0)
    }
}
