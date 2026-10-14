import Foundation
import Testing

@testable import PodlistKit

struct ShowNotesTimestampsTests {
    private func found(_ text: String) -> [String] {
        ShowNotesTimestamps.matches(in: text).map { String(text[$0.range]) }
    }

    @Test(arguments: [
        ("0:05", 5.0), ("12:34", 754), ("1:02:03", 3723), ("00:00:00", 0), ("01:30:00", 5400),
        ("120:00", 7200), ("999:59", 59999), ("00:00", 0),
    ])
    func parsesTimes(_ text: String, _ seconds: TimeInterval) {
        let matches = ShowNotesTimestamps.matches(in: "at \(text) ok")
        #expect(matches.count == 1)
        #expect(matches.first?.time == seconds)
    }

    @Test(arguments: [
        ("Thema (12:34)", ["12:34"]),
        ("12:34 Thema, 1:02:03 anderes", ["12:34", "1:02:03"]),
        ("[00:10] Intro", ["00:10"]),
        ("Um 12:34, dann 5:00.", ["12:34", "5:00"]),
        ("12:34-15:00", ["12:34", "15:00"]),
        ("1:2:3:4", []),
        ("12:345", []),
        ("1234:56", []),
        ("a12:34", []),
        ("12:34b", []),
        ("x 12:34:", ["12:34"]),
        ("12:34:5", []),
        ("12:60", []),
        ("1:02:75", []),
        ("1:75:00", []),
        ("12:5", []),
        ("Uhr: 12", []),
        ("", []),
    ])
    func matching(_ text: String, _ expected: [String]) {
        #expect(found(text) == expected)
    }

    @Test(arguments: [0.0, 5, 754, 3723, 86399])
    func urlRoundTrip(_ time: TimeInterval) {
        let url = ShowNotesTimestamps.url(for: time)
        #expect(url.scheme == "podlist-time")
        #expect(ShowNotesTimestamps.time(from: url) == time)
    }

    @Test func urlFormat() {
        #expect(ShowNotesTimestamps.url(for: 754).absoluteString == "podlist-time:754")
        #expect(ShowNotesTimestamps.url(for: 754.9).absoluteString == "podlist-time:754")
    }

    @Test(arguments: ["https://example.com/754", "podlist-time:abc", "podlist-time:-4", "podlist-time:"])
    func foreignUrlsGiveNil(_ text: String) throws {
        let url = try #require(URL(string: text))
        #expect(ShowNotesTimestamps.time(from: url) == nil)
    }

    // MARK: Chapters

    private func titles(_ text: String, duration: TimeInterval? = nil) -> [String] {
        ShowNotesTimestamps.chapters(inPlainText: text, duration: duration).map(\.title)
    }

    @Test func leadingTimestamps() {
        let text = """
            Intro text

            00:00 Intro
            05:30 - Erstes Thema
            1:02:03 – Zweites Thema
            """
        let chapters = ShowNotesTimestamps.chapters(inPlainText: text, duration: 4000)
        #expect(chapters.map(\.title) == ["Intro", "Erstes Thema", "Zweites Thema"])
        #expect(chapters.map(\.start) == [0, 330, 3723])
        #expect(chapters.allSatisfy { $0.end == nil && !$0.isHidden && $0.imageURL == nil && $0.linkURL == nil })
    }

    @Test(arguments: [
        "- 00:00 Intro\n- 01:00 Eins\n- 02:00 Zwei",
        "• 00:00 Intro\n• 01:00 Eins\n• 02:00 Zwei",
        "* 00:00 Intro\n* 01:00 Eins\n* 02:00 Zwei",
        "(00:00) Intro\n(01:00) Eins\n(02:00) Zwei",
        "[00:00] Intro\n[01:00] Eins\n[02:00] Zwei",
        "00:00: Intro\n01:00 | Eins\n02:00 — Zwei",
        "  00:00   Intro  \n\n01:00\tEins\r\n02:00 Zwei",
    ])
    func leadingVariants(_ text: String) {
        #expect(titles(text) == ["Intro", "Eins", "Zwei"])
    }

    @Test(arguments: [
        "Intro (00:00)\nEins (01:00)\nZwei (02:00)",
        "Intro - 00:00\nEins - 01:00\nZwei - 02:00",
        "Intro [00:00]\nEins [01:00]\nZwei [02:00]",
        "Intro: 00:00\nEins | 01:00\nZwei — 02:00",
        "• Intro (00:00)\n• Eins (01:00)\n• Zwei (02:00)",
    ])
    func trailingVariants(_ text: String) {
        #expect(titles(text) == ["Intro", "Eins", "Zwei"])
    }

    @Test func mixedLeadingAndTrailing() {
        #expect(titles("00:00 Intro\nEins (01:00)\n02:00 Zwei") == ["Intro", "Eins", "Zwei"])
    }

    @Test func otherLinesAreIgnored() {
        let text = "Willkommen\n00:00 Intro\nZwischentext ohne Zeit\n01:00 Eins\n02:00 Zwei\nBis bald!"
        #expect(titles(text) == ["Intro", "Eins", "Zwei"])
    }

    @Test(arguments: [
        // Fewer than 3 lines
        "00:00 Intro\n01:00 Eins",
        "",
        "kein Zeitstempel hier",
        // Not strictly increasing
        "00:00 A\n01:00 B\n01:00 C",
        "00:00 A\n02:00 B\n01:00 C",
        // Timestamp without title
        "00:00\n01:00\n02:00",
        "00:00 -\n01:00 –\n02:00 :",
        // Timestamps in running text, not at a line edge
        "Wir sprechen um 00:00 Uhr kurz und um 01:00 Uhr lang\nund um 02:00 Uhr nochmal\nund 03:00 Uhr",
    ])
    func implausible(_ text: String) {
        #expect(titles(text) == [])
    }

    @Test func durationLimit() {
        let text = "00:00 A\n01:00 B\n02:00 C"
        #expect(titles(text, duration: 121) == ["A", "B", "C"])
        #expect(titles(text, duration: 120) == [])
        #expect(titles(text, duration: 60) == [])
        #expect(titles(text, duration: nil) == ["A", "B", "C"])
    }

    @Test func leadingTimestampWinsOverEmbeddedOne() {
        let text = "00:00 Intro\n01:00 Eins (bei 05:00 wichtig)\n02:00 Zwei"
        #expect(titles(text) == ["Intro", "Eins (bei 05:00 wichtig)", "Zwei"])
    }
}
