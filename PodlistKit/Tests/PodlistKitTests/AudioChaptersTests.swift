import Foundation
import Testing
@testable import PodlistKit

/// Fixtures: scripts/make-chapter-fixture.sh and scripts/make-id3-chapter-fixtures.py.
struct AudioChaptersTests {
    struct Case: Sendable, CustomTestStringConvertible {
        var name: String
        var ext = "mp3"
        var source: ChapterSource = .id3
        var titles = ["Intro", "Zweites Kapitel", "Abschluss"]
        var links = false
        var images = false
        var testDescription: String { name }
    }

    static let richTitles = ["Intro", "Zweites Kapitel", "Abschluss \u{00FC}ber alles"]
    static let links = ["https://example.com/intro", "https://example.com/zwei", "https://example.com/ende"]

    static let cases: [Case] = [
        Case(name: "chapters-id3"),
        Case(name: "chapters-id3-rich-v23", titles: richTitles, links: true, images: true),
        Case(name: "chapters-id3-small-v24", titles: richTitles, links: true),
        Case(name: "chapters-id3-trailing", titles: richTitles, links: true),
        Case(name: "chapters-mp4", ext: "m4a", source: .mp4),
    ]

    static func url(_ name: String, _ ext: String = "mp3") throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures"))
    }

    @Test(arguments: cases)
    func loadsChaptersFromFixture(_ fixture: Case) async throws {
        let result = try #require(try await AudioChapters.load(from: Self.url(fixture.name, fixture.ext)))
        #expect(result.source == fixture.source)
        #expect(result.chapters.map(\.title) == fixture.titles)
        let starts = result.chapters.map(\.start)
        let ends = result.chapters.map { $0.end ?? -1 }
        #expect(zip(starts, [0, 2, 4.5]).allSatisfy { abs($0 - $1) < 0.01 })
        #expect(zip(ends, [2, 4.5, 6]).allSatisfy { abs($0 - $1) < 0.01 })
        #expect(result.chapters.allSatisfy { $0.imageURL == nil && !$0.isHidden })
        #expect(result.chapters.map(\.linkURL?.absoluteString) == (fixture.links ? Self.links : [nil, nil, nil]))
        if fixture.images {
            #expect(result.images.keys.sorted() == [0, 1, 2])
            #expect(result.images.values.allSatisfy { $0.starts(with: [0x89, 0x50, 0x4E, 0x47]) })
        } else {
            #expect(result.images.isEmpty)
        }
    }

    /// Spec-compliant ID3v2.4 with large CHAP sub-frames: AVFoundation delivers nothing (see ChapterSpikeTests).
    @Test func richID3v24YieldsNothingBecauseAVFoundationDeliversNothing() async throws {
        #expect(try await AudioChapters.load(from: Self.url("chapters-id3-rich-v24")) == nil)
    }

    @Test func fileWithoutChaptersYieldsNil() async throws {
        // The fixture's audio frames without any ID3 tag.
        let data = try Data(contentsOf: Self.url("chapters-id3"))
        let size = data[6..<10].reduce(0) { ($0 << 7) | Int($1) }
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let plain = dir.appending(path: "plain.mp3")
        try data.dropFirst(10 + size).write(to: plain)
        #expect(try await AudioChapters.load(from: plain) == nil)
    }

    @Test func missingFileThrows() async {
        let missing = URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).mp3")
        await #expect(throws: (any Error).self) { try await AudioChapters.load(from: missing) }
    }

    @Test(arguments: [
        (["de-DE", "en-US"], ["en", "de", "fr"], ["de", "en", "fr"]),
        (["fr"], ["en", "de"], ["en", "de"]),
        (["en"], ["und"], ["und"]),
        ([], ["de", "en"], ["de", "en"]),
    ] as [([String], [String], [String])])
    func localeOrderPrefersUserLanguageAmongAvailable(preferred: [String], available: [String], expected: [String]) {
        #expect(AudioChapters.orderedLocaleIdentifiers(available: available, preferred: preferred) == expected)
    }

    @Test(arguments: [
        ("https://example.com/a", "https://example.com/a"),
        (" http://example.com/b \n", "http://example.com/b"),
        ("javascript:alert(1)", nil),
        ("tel:+4912345", nil),
        ("file:///etc/passwd", nil),
        ("example.com/no-scheme", nil),
        ("", nil),
    ] as [(String, String?)])
    func onlyWebLinksAreAccepted(input: String, expected: String?) {
        #expect(AudioChapters.webURL(input)?.absoluteString == expected)
    }
}
