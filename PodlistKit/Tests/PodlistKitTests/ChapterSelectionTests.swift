import Foundation
import Testing
@testable import PodlistKit

struct ChapterSelectionTests {
    private func ch(
        _ start: Double, _ title: String = "", end: Double? = nil,
        image: String? = nil, link: String? = nil, hidden: Bool = false
    ) -> Chapter {
        Chapter(
            start: start, end: end, title: title,
            imageURL: image.flatMap(URL.init(string:)), linkURL: link.flatMap(URL.init(string:)),
            isHidden: hidden)
    }

    private func starts(_ chapters: [Chapter]) -> [Double] { chapters.map(\.start) }

    // MARK: Priority

    @Test func priorityOrderIsJsonPodloveId3Mp4Shownotes() {
        let order: [ChapterSource] = [.json, .podlove, .id3, .mp4, .shownotes]
        let priorities = order.map(ChapterSelection.priority(of:))
        #expect(priorities == priorities.sorted(by: >))
        #expect(Set(priorities).count == order.count)
    }

    @Test(arguments: ChapterSource.allCases, ChapterSource.allCases)
    func shouldReplaceAllPairs(current: ChapterSource, candidate: ChapterSource) {
        let expected = ChapterSelection.priority(of: candidate) >= ChapterSelection.priority(of: current)
        #expect(ChapterSelection.shouldReplace(current, with: candidate) == expected)
    }

    @Test(arguments: ChapterSource.allCases)
    func nothingStoredIsAlwaysReplaced(candidate: ChapterSource) {
        #expect(ChapterSelection.shouldReplace(nil, with: candidate))
    }

    @Test func shouldReplaceExamples() {
        #expect(ChapterSelection.shouldReplace(.shownotes, with: .id3))
        #expect(!ChapterSelection.shouldReplace(.json, with: .id3))
        #expect(ChapterSelection.shouldReplace(.json, with: .json))
    }

    // MARK: Normalized

    @Test func sortsByStart() {
        let result = ChapterSelection.normalized([ch(60, "b"), ch(0, "a"), ch(30, "c")], duration: 100)
        #expect(result.map(\.title) == ["a", "c", "b"])
    }

    @Test func dropsInvalidStarts() {
        let input = [ch(-1), ch(.nan), ch(.infinity), ch(0, "ok"), ch(100), ch(150)]
        #expect(starts(ChapterSelection.normalized(input, duration: 100)) == [0])
    }

    @Test func unknownDurationKeepsLateChapters() {
        let result = ChapterSelection.normalized([ch(0, "a"), ch(5000, "b")], duration: nil)
        #expect(starts(result) == [0, 5000])
        #expect(result.last?.end == nil)
    }

    @Test func duplicateVisibleStartsKeepFirst() {
        let result = ChapterSelection.normalized([ch(0, "first"), ch(0, "second"), ch(10, "c")], duration: 100)
        #expect(result.map(\.title) == ["first", "c"])
    }

    @Test func titlesAreTrimmed() {
        let result = ChapterSelection.normalized([ch(0, "  Hello\n"), ch(10, " \n ")], duration: nil)
        #expect(result.map(\.title) == ["Hello", ""])
    }

    @Test func visibleEndsAreNextVisibleStartAndLastUsesDuration() {
        let result = ChapterSelection.normalized([ch(0, end: 5), ch(60), ch(120)], duration: 200)
        #expect(result.map(\.end) == [60, 120, 200])
    }

    @Test(arguments: [
        (150.0 as Double?, 200.0 as Double?, 150.0 as Double?), // own end kept
        (nil, 200.0, 200.0), // no end -> duration
        (50.0, 200.0, 200.0), // end <= start -> duration
        (500.0, 200.0, 200.0), // clamped to duration
        (nil, nil, nil), // nothing known
        (150.0, nil, 150.0), // own end kept, unknown duration
    ])
    func lastVisibleEnd(ownEnd: Double?, duration: Double?, expected: Double?) {
        let result = ChapterSelection.normalized([ch(0), ch(100, end: ownEnd)], duration: duration)
        #expect(result.last?.end == expected)
    }

    @Test func hiddenChapterKeepsOwnEndAndDoesNotShortenVisible() {
        let input = [ch(0, "a"), ch(20, "img", end: 40, image: "https://x/i.png", hidden: true), ch(60, "b")]
        let result = ChapterSelection.normalized(input, duration: 100)
        #expect(result.map(\.end) == [60, 40, 100])
    }

    @Test(arguments: [(nil as Double?, nil as Double?), (10.0, nil), (20.0, nil), (500.0, 100.0)])
    func hiddenInvalidEndIsNilAndClamped(end: Double?, expected: Double?) {
        let result = ChapterSelection.normalized([ch(0), ch(20, end: end, hidden: true)], duration: 100)
        #expect(result.last?.end == expected)
    }

    @Test func hiddenWithSameStartAsVisibleIsKept() {
        let result = ChapterSelection.normalized([ch(0, "v"), ch(0, "h", end: 5, hidden: true)], duration: 100)
        #expect(result.count == 2)
    }

    @Test func noVisibleChapterYieldsEmpty() {
        #expect(ChapterSelection.normalized([ch(0, hidden: true)], duration: 100).isEmpty)
        #expect(ChapterSelection.normalized([], duration: 100).isEmpty)
        #expect(ChapterSelection.normalized([ch(200)], duration: 100).isEmpty)
    }

    // MARK: Visible / context

    @Test func visibleDropsHidden() {
        #expect(starts(ChapterSelection.visible([ch(0), ch(5, hidden: true), ch(10)])) == [0, 10])
    }

    private var contextChapters: [Chapter] {
        ChapterSelection.normalized([
            ch(10, "a", image: "https://x/a.png", link: "https://x/a"),
            ch(30, "img", end: 40, image: "https://x/h.png", hidden: true),
            ch(60, "b"),
            ch(90, "c", image: "https://x/c.png"),
        ], duration: 120)
    }

    @Test(arguments: [
        (0.0, nil as Int?), (9.99, nil), (10.0, 0), (59.99, 0), (60.0, 1), (89.0, 1), (90.0, 2), (500.0, 2),
    ])
    func contextIndex(time: Double, expected: Int?) {
        let context = ChapterSelection.context(at: time, in: contextChapters)
        #expect(context.index == expected)
        #expect(context.chapter?.start == expected.map { [10.0, 60, 90][$0] })
    }

    @Test(arguments: [
        (5.0, nil as String?), (10.0, "https://x/a.png"), (29.0, "https://x/a.png"),
        (30.0, "https://x/h.png"), (39.9, "https://x/h.png"), (40.0, "https://x/a.png"),
        (60.0, nil), (89.0, nil), (90.0, "https://x/c.png"),
    ])
    func contextImage(time: Double, expected: String?) {
        #expect(ChapterSelection.context(at: time, in: contextChapters).imageURL?.absoluteString == expected)
    }

    @Test(arguments: [(5.0, nil as String?), (10.0, "https://x/a"), (35.0, "https://x/a"), (60.0, nil)])
    func contextLink(time: Double, expected: String?) {
        #expect(ChapterSelection.context(at: time, in: contextChapters).linkURL?.absoluteString == expected)
    }

    @Test func contextTieOnStartLaterInArrayWins() {
        let chapters = [
            ch(0, "v", end: 50, image: "https://x/1.png"),
            ch(0, "h", end: 50, image: "https://x/2.png", hidden: true),
        ]
        #expect(ChapterSelection.context(at: 10, in: chapters).imageURL?.absoluteString == "https://x/2.png")
    }

    @Test func contextWithoutChapters() {
        #expect(ChapterSelection.context(at: 10, in: []) == ChapterContext())
    }

    // MARK: Next / previous

    private var three: [Chapter] { ChapterSelection.normalized([ch(0), ch(60), ch(120)], duration: 200) }

    @Test(arguments: [
        (-5.0, 0.0 as Double?), (0.0, 60), (30.0, 60), (58.9, 60), (59.0, 120), (59.99, 120), (60.0, 120),
        (61.5, 120), (118.9, 120), (119.0, nil), (120.0, nil), (190.0, nil),
    ])
    func nextStartWithTolerance(time: Double, expected: Double?) {
        #expect(ChapterSelection.nextStart(after: time, in: three) == expected)
    }

    @Test func nextStartCustomToleranceAndEmpty() {
        #expect(ChapterSelection.nextStart(after: 59.99, in: three, tolerance: 0) == 60)
        #expect(ChapterSelection.nextStart(after: 10, in: []) == nil)
    }

    @Test func nextStartSkipsHidden() {
        let chapters = ChapterSelection.normalized([ch(0), ch(30, hidden: true), ch(60)], duration: 100)
        #expect(ChapterSelection.nextStart(after: 10, in: chapters) == 60)
    }

    @Test(arguments: [
        (0.0, 0.0), (2.0, 0.0), (3.5, 0.0), (30.0, 0.0), // first chapter: always its start
        (60.0, 0.0), (62.9, 0.0), (63.0, 0.0), (63.1, 60.0), (100.0, 60.0), // second chapter
        (120.0, 60.0), (123.0, 60.0), (123.5, 120.0), (190.0, 120.0), // third chapter
    ])
    func previousStart(time: Double, expected: Double) {
        #expect(ChapterSelection.previousStart(before: time, in: three) == expected)
    }

    @Test func previousStartBeforeFirstChapterAndWithoutChapters() {
        let chapters = ChapterSelection.normalized([ch(20), ch(80)], duration: 200)
        #expect(ChapterSelection.previousStart(before: 5, in: chapters) == 20)
        #expect(ChapterSelection.previousStart(before: 20, in: chapters) == 20)
        #expect(ChapterSelection.previousStart(before: 50, in: []) == 0)
    }

    @Test func previousStartCustomThresholdAndHidden() {
        let chapters = ChapterSelection.normalized([ch(0), ch(30, hidden: true), ch(60)], duration: 200)
        #expect(ChapterSelection.previousStart(before: 70, in: chapters, restartThreshold: 5) == 60)
        #expect(ChapterSelection.previousStart(before: 70, in: chapters, restartThreshold: 15) == 0)
        #expect(ChapterSelection.previousStart(before: 62, in: chapters, restartThreshold: 1) == 60)
    }
}
