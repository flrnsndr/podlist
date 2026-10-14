import Foundation

/// Clock timestamps in show notes: finding them, tapping them, and the chapter heuristic (concept §4.6, A31).
public enum ShowNotesTimestamps {
    public struct Match: Hashable, Sendable {
        public var range: Range<String.Index>
        public var time: TimeInterval

        public init(range: Range<String.Index>, time: TimeInterval) {
            self.range = range
            self.time = time
        }
    }

    // MARK: Matching

    /// Every clock timestamp in plain text: `H:MM:SS`, `HH:MM:SS`, `M:SS`, `MM:SS`, `MMM:SS`.
    /// Not when glued to other digits, letters, or a further `:digit` (e.g. not inside `1:2:3:4` or `12:345`).
    public static func matches(in text: String) -> [Match] {
        var result: [Match] = []
        var index = text.startIndex
        var previous: Character?
        while index < text.endIndex {
            let c = text[index]
            if c.isASCII, c.isNumber, previous.map({ !isGlue($0) }) ?? true,
                let (match, end) = timestamp(in: text, at: index)
            {
                result.append(match)
                previous = text[text.index(before: end)]
                index = end
            } else {
                previous = c
                index = text.index(after: index)
            }
        }
        return result
    }

    /// Characters a timestamp must not directly follow.
    private static func isGlue(_ c: Character) -> Bool {
        c == ":" || c.isLetter || (c.isASCII && c.isNumber)
    }

    /// Reads `d{1,3}:dd` or `d{1,2}:dd:dd` starting at `start`, and checks what follows.
    private static func timestamp(in text: String, at start: String.Index) -> (Match, String.Index)? {
        func digits(from index: String.Index, max limit: Int) -> (value: Int, count: Int, end: String.Index) {
            var value = 0
            var count = 0
            var i = index
            while i < text.endIndex, text[i].isASCII, let d = text[i].wholeNumberValue {
                value = value * 10 + d
                count += 1
                i = text.index(after: i)
                if count > limit { break }
            }
            return (value, count, i)
        }

        let first = digits(from: start, max: 3)
        guard (1...3).contains(first.count), first.end < text.endIndex, text[first.end] == ":" else { return nil }
        let secondStart = text.index(after: first.end)
        let second = digits(from: secondStart, max: 2)
        guard second.count == 2, second.value < 60 else { return nil }

        var end = second.end
        var seconds = Double(first.value * 60 + second.value)
        // Three parts: only if the first group is an hour (1-2 digits) and the next two digits follow.
        if first.count <= 2, end < text.endIndex, text[end] == ":" {
            let third = digits(from: text.index(after: end), max: 2)
            if third.count == 2, third.value < 60, second.value < 60 {
                end = third.end
                seconds = Double(first.value * 3600 + second.value * 60 + third.value)
            }
        }

        if end < text.endIndex {
            let next = text[end]
            if next.isLetter || (next.isASCII && next.isNumber) { return nil }
            if next == ":", let after = Optional(text.index(after: end)), after < text.endIndex,
                text[after].isASCII, text[after].isNumber
            {
                return nil
            }
        }
        return (Match(range: start..<end, time: seconds), end)
    }

    // MARK: Links

    private static let scheme = "podlist-time"

    /// Link target for a tappable timestamp, e.g. `podlist-time:754` (whole seconds).
    public static func url(for time: TimeInterval) -> URL {
        let seconds = time.isFinite ? max(0, Int(time)) : 0
        // The string is always a valid URL.
        return URL(string: "\(scheme):\(seconds)")!
    }

    public static func time(from url: URL) -> TimeInterval? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let rest = url.absoluteString.dropFirst(scheme.count + 1)
        guard !rest.isEmpty, rest.allSatisfy({ $0.isASCII && $0.isNumber }), let seconds = Int(rest) else { return nil }
        return TimeInterval(seconds)
    }

    // MARK: Heuristic chapters

    private static let leadingNoise: Set<Character> = ["-", "–", "—", "•", "*", "(", "[", " ", "\t", "\u{00A0}"]
    private static let separatorsAfterTime: Set<Character> = ["-", "–", "—", ":", "|", ")", "]", " ", "\t", "\u{00A0}"]
    private static let trailingClosers: Set<Character> = [")", "]", " ", "\t", "\u{00A0}"]
    private static let separatorsBeforeTime: Set<Character> = ["-", "–", "—", ":", "|", "(", "[", " ", "\t", "\u{00A0}"]

    /// Lines of the form `12:34 Title` (after optional bullets or brackets) or `Title (12:34)`.
    /// Plausible only with at least 3 such lines, strictly increasing times, all before `duration` if known;
    /// otherwise `[]`.
    public static func chapters(inPlainText text: String, duration: TimeInterval?) -> [Chapter] {
        var found: [Chapter] = []
        for line in text.split(whereSeparator: \.isNewline) {
            if let chapter = chapter(inLine: String(line)) { found.append(chapter) }
        }
        guard found.count >= 3 else { return [] }
        for (index, chapter) in found.enumerated() {
            if index > 0, chapter.start <= found[index - 1].start { return [] }
            if let duration, chapter.start >= duration { return [] }
        }
        return found
    }

    private static func chapter(inLine line: String) -> Chapter? {
        let body = String(line.drop(while: { leadingNoise.contains($0) }))
        let all = matches(in: body)
        guard let first = all.first else { return nil }

        if first.range.lowerBound == body.startIndex {
            let title = clean(body[first.range.upperBound...], dropping: separatorsAfterTime, fromStart: true)
            return title.isEmpty ? nil : Chapter(start: first.time, title: title)
        }

        var end = body.endIndex
        while end > body.startIndex, trailingClosers.contains(body[body.index(before: end)]) {
            end = body.index(before: end)
        }
        if let last = all.last, last.range.upperBound == end {
            let title = clean(body[..<last.range.lowerBound], dropping: separatorsBeforeTime, fromStart: false)
            return title.isEmpty ? nil : Chapter(start: last.time, title: title)
        }
        return nil
    }

    private static func clean(_ part: Substring, dropping set: Set<Character>, fromStart: Bool) -> String {
        var result = part
        if fromStart {
            result = result.drop(while: { set.contains($0) })
        } else {
            while let last = result.last, set.contains(last) { result = result.dropLast() }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
