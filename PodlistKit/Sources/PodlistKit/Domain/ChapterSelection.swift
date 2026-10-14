import Foundation

/// What is current at a playback time.
public struct ChapterContext: Hashable, Sendable {
    /// Index into `ChapterSelection.visible(chapters)`; nil before the first visible chapter or without chapters.
    public var index: Int?
    public var chapter: Chapter?
    public var imageURL: URL?
    public var linkURL: URL?
    public init(index: Int? = nil, chapter: Chapter? = nil, imageURL: URL? = nil, linkURL: URL? = nil) {
        self.index = index
        self.chapter = chapter
        self.imageURL = imageURL
        self.linkURL = linkURL
    }
}

/// Chapter source priority, normalization and navigation (concept §4.6, ADR 0005).
public enum ChapterSelection {
    /// ADR 0005: json > podlove > id3 > mp4 > shownotes (higher = better).
    public static func priority(of source: ChapterSource) -> Int {
        switch source {
        case .json: 5
        case .podlove: 4
        case .id3: 3
        case .mp4: 2
        case .shownotes: 1
        }
    }

    /// Whether chapters from `candidate` replace stored chapters from `current` (nil = nothing stored).
    /// Same source replaces (an update).
    public static func shouldReplace(_ current: ChapterSource?, with candidate: ChapterSource) -> Bool {
        guard let current else { return true }
        return priority(of: candidate) >= priority(of: current)
    }

    public static func normalized(_ chapters: [Chapter], duration: TimeInterval?) -> [Chapter] {
        func clamped(_ value: TimeInterval) -> TimeInterval {
            duration.map { min(value, $0) } ?? value
        }
        let valid = chapters.enumerated().filter { _, chapter in
            guard chapter.start.isFinite, chapter.start >= 0 else { return false }
            if let duration, chapter.start >= duration { return false }
            return true
        }
        // Stable sort: equal starts keep input order.
        let sorted = valid.sorted { a, b in
            a.element.start != b.element.start ? a.element.start < b.element.start : a.offset < b.offset
        }.map(\.element)

        var seenVisibleStarts = Set<TimeInterval>()
        var kept: [Chapter] = []
        for var chapter in sorted {
            if !chapter.isHidden, !seenVisibleStarts.insert(chapter.start).inserted { continue }
            chapter.title = chapter.title.trimmingCharacters(in: .whitespacesAndNewlines)
            kept.append(chapter)
        }

        let visibleIndices = kept.indices.filter { !kept[$0].isHidden }
        guard !visibleIndices.isEmpty else { return [] }
        for index in kept.indices where kept[index].isHidden {
            let start = kept[index].start
            kept[index].end = kept[index].end.flatMap { $0 > start ? clamped($0) : nil }
        }
        for (n, index) in visibleIndices.enumerated() {
            if n + 1 < visibleIndices.count {
                kept[index].end = kept[visibleIndices[n + 1]].start
            } else if let own = kept[index].end, own > kept[index].start {
                kept[index].end = clamped(own)
            } else {
                kept[index].end = duration
            }
        }
        return kept
    }

    /// Chapters that appear in the list (not `isHidden`), in order.
    public static func visible(_ chapters: [Chapter]) -> [Chapter] {
        chapters.filter { !$0.isHidden }
    }

    public static func context(at time: TimeInterval, in chapters: [Chapter]) -> ChapterContext {
        let list = visible(chapters)
        let index = list.lastIndex { $0.start <= time }

        func latest(_ url: KeyPath<Chapter, URL?>) -> URL? {
            var best: Chapter?
            for chapter in chapters where chapter.start <= time && chapter[keyPath: url] != nil {
                if let end = chapter.end, time >= end { continue }
                // `>=`: on equal starts the later chapter in the array wins.
                if let current = best, chapter.start < current.start { continue }
                best = chapter
            }
            return best?[keyPath: url]
        }
        return ChapterContext(
            index: index, chapter: index.map { list[$0] },
            imageURL: latest(\.imageURL), linkURL: latest(\.linkURL))
    }

    /// Start of the next visible chapter that begins more than `tolerance` after `time`; nil at the last one.
    public static func nextStart(
        after time: TimeInterval, in chapters: [Chapter], tolerance: TimeInterval = 1
    ) -> TimeInterval? {
        visible(chapters).first { $0.start > time + tolerance }?.start
    }

    /// "Previous chapter" button: more than `restartThreshold` into the current visible chapter → its start;
    /// otherwise the previous visible chapter's start; before/at the first chapter → the first chapter's start,
    /// or 0 without chapters.
    public static func previousStart(
        before time: TimeInterval, in chapters: [Chapter], restartThreshold: TimeInterval = 3
    ) -> TimeInterval {
        let list = visible(chapters)
        guard let first = list.first else { return 0 }
        guard let index = list.lastIndex(where: { $0.start <= time }) else { return first.start }
        if time - list[index].start > restartThreshold || index == 0 { return list[index].start }
        return list[index - 1].start
    }
}
