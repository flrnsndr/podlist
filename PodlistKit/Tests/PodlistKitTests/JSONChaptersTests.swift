import Foundation
import Testing

@testable import PodlistKit

struct JSONChaptersTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/Chapters"))
        return try Data(contentsOf: url)
    }

    private let base = URL(string: "https://example.com/podcast/chapters/ep42.json")

    @Test func specExample() throws {
        let chapters = try JSONChapters.parse(fixture("spec-example"), baseURL: base)
        #expect(chapters.count == 5)
        #expect(chapters[0] == Chapter(start: 0, title: "Intro"))
        #expect(chapters[1].start == 45.5)
        #expect(chapters[1].title == "Begrüßung und Neuigkeiten")
        #expect(chapters[1].imageURL == URL(string: "https://example.com/img/news.jpg"))
        #expect(chapters[1].linkURL == URL(string: "https://example.com/news"))
        #expect(!chapters[1].isHidden)
        #expect(chapters[2].isHidden)
        #expect(chapters[2].end == 660)
        #expect(chapters[2].title == "Werbung")
        #expect(chapters[3] == Chapter(start: 660, title: "Interview mit Anna"))
        #expect(chapters[4].start == 1800.25)
        #expect(chapters[4].end == 2400)
    }

    @Test func relativePathsResolveAgainstBase() throws {
        let chapters = try JSONChapters.parse(fixture("relative-paths"), baseURL: base)
        #expect(chapters.count == 3)
        #expect(chapters[0].imageURL == URL(string: "https://example.com/podcast/chapters/images/start.jpg"))
        #expect(chapters[1].imageURL == URL(string: "https://example.com/covers/mid.png"))
        #expect(chapters[1].linkURL == URL(string: "https://example.com/podcast/links/mid.html"))
        // Non-web schemes are dropped.
        #expect(chapters[2].imageURL == nil)
        #expect(chapters[2].linkURL == nil)
    }

    @Test func relativePathsWithoutBaseAreDropped() throws {
        let chapters = try JSONChapters.parse(fixture("relative-paths"), baseURL: nil)
        #expect(chapters.count == 3)
        #expect(chapters.allSatisfy { $0.imageURL == nil && $0.linkURL == nil })
    }

    @Test func entriesWithoutUsableStartAreSkippedAndOrderIsKept() throws {
        let chapters = try JSONChapters.parse(fixture("messy-entries"), baseURL: base)
        #expect(chapters.map(\.start) == [10, 20, 5])
        #expect(chapters[0].title == "")
        #expect(chapters[1].end == nil)
    }

    @Test func emptyChaptersArrayIsValid() throws {
        #expect(try JSONChapters.parse(Data(#"{"chapters": []}"#.utf8), baseURL: nil) == [])
    }

    @Test(arguments: [
        "",
        "not json",
        "[]",
        #"{"version": "1.2.0"}"#,
        #"{"chapters": {"startTime": 0}}"#,
        #"{"chapters": null}"#,
        #"[{"startTime": 0}]"#,
        "42",
    ])
    func invalidDocuments(_ text: String) {
        #expect(throws: JSONChaptersError.invalid) {
            try JSONChapters.parse(Data(text.utf8), baseURL: nil)
        }
    }

    @Test func invalidFixture() throws {
        let data = try fixture("invalid")
        #expect(throws: JSONChaptersError.invalid) { try JSONChapters.parse(data, baseURL: base) }
    }

    @Test(arguments: [
        (#"{"chapters":[{"startTime":-5,"title":"x"}]}"#, 0),
        (#"{"chapters":[{"startTime":"  12 ","title":"x"}]}"#, 1),
        (#"{"chapters":[{"startTime":true,"title":"x"}]}"#, 0),
        (#"{"chapters":[{"startTime":null,"title":"x"}]}"#, 0),
    ])
    func startTimeVariants(_ text: String, _ count: Int) throws {
        #expect(try JSONChapters.parse(Data(text.utf8), baseURL: nil).count == count)
    }
}
