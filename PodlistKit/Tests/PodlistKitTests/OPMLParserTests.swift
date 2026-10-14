import Foundation
import Testing

@testable import PodlistKit

struct OPMLParserTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "opml", subdirectory: "Fixtures/OPML"))
        return try Data(contentsOf: url)
    }

    private func parse(_ xml: String) throws -> [OPMLOutline] {
        try OPMLParser.parse(Data(xml.utf8))
    }

    @Test func pocketCasts() throws {
        let result = try OPMLParser.parse(fixture("pocketcasts"))
        #expect(
            result == [
                OPMLOutline(title: "Lage der Nation", feedURL: URL(string: "https://feeds.lagedernation.org/feed.xml")!),
                OPMLOutline(title: "Radiolab", feedURL: URL(string: "https://feeds.simplecast.com/EZHmfYtM")!),
                // `text` is blank, so `title` is the fallback.
                OPMLOutline(title: "Fallback Title", feedURL: URL(string: "http://example.com/feed.rss")!),
            ])
    }

    @Test func overcastNestedWithEpisodes() throws {
        let result = try OPMLParser.parse(fixture("overcast"))
        #expect(
            result.map(\.feedURL.absoluteString) == [
                "https://feeds.99percentinvisible.org/99percentinvisible",
                "https://feeds.feedburner.com/dancarlin/history",
            ])
        #expect(result.map(\.title) == ["99% Invisible", "Hardcore History"])
    }

    @Test func applePodcastsStyle() throws {
        let result = try OPMLParser.parse(fixture("applepodcasts"))
        #expect(result.map(\.title) == ["Cortex", "Accidental Tech Podcast", "Link Typed"])
        #expect(result[2].feedURL.absoluteString == "https://example.com/link.xml")
    }

    @Test func entitiesAndUmlauts() throws {
        let result = try OPMLParser.parse(fixture("entities"))
        #expect(result.map(\.title) == ["Müller & Söhne: Über Äpfel \"und\" Birnen", "Fußball – Das Spiel 🏆"])
        #expect(result[0].feedURL.absoluteString == "https://example.com/a.xml?x=1&y=2")
    }

    @Test func nonOPMLRoot() throws {
        let data = try fixture("notopml")
        #expect(throws: OPMLParserError.notOPML) { try OPMLParser.parse(data) }
    }

    @Test func truncatedIsMalformed() throws {
        let data = try fixture("truncated")
        #expect {
            try OPMLParser.parse(data)
        } throws: { error in
            guard case .malformed = error as? OPMLParserError else { return false }
            return true
        }
    }

    @Test func emptyDataIsMalformed() {
        #expect {
            try OPMLParser.parse(Data())
        } throws: { error in
            guard case .malformed = error as? OPMLParserError else { return false }
            return true
        }
    }

    @Test func emptyBodyYieldsNothing() throws {
        #expect(try parse("<opml version=\"2.0\"><body/></opml>").isEmpty)
    }

    struct TitleCase: Sendable, CustomTestStringConvertible {
        let attributes: String
        let expected: String?
        var testDescription: String { attributes }
    }

    @Test(arguments: [
        TitleCase(attributes: "text=\"A\" title=\"B\"", expected: "A"),
        TitleCase(attributes: "title=\"B\"", expected: "B"),
        TitleCase(attributes: "text=\"  padded \n\"", expected: "padded"),
        TitleCase(attributes: "text=\"\" title=\" \"", expected: nil),
        TitleCase(attributes: "", expected: nil),
    ])
    func titleRules(_ c: TitleCase) throws {
        let result = try parse(
            "<opml><body><outline \(c.attributes) xmlUrl=\"https://e.com/f\"/></body></opml>")
        #expect(result.count == 1)
        #expect(result.first?.title == c.expected)
    }

    @Test(arguments: [
        ("https://e.com/f", true),
        ("http://e.com/f", true),
        ("HTTPS://e.com/f", true),
        ("  https://e.com/f  ", true),
        ("ftp://e.com/f", false),
        ("feed://e.com/f", false),
        ("/relative.xml", false),
        ("e.com/f", false),
        ("https://", false),
        ("", false),
    ])
    func urlRules(_ value: String, _ accepted: Bool) throws {
        let result = try parse("<opml><body><outline text=\"X\" xmlUrl=\"\(value)\"/></body></opml>")
        #expect(result.count == (accepted ? 1 : 0))
    }

    @Test(arguments: [("rss", true), ("link", true), ("", true), ("podcastEpisode", false), ("podcast-episode", false)])
    func typeRules(_ type: String, _ accepted: Bool) throws {
        let typeAttr = type.isEmpty ? "" : "type=\"\(type)\""
        let result = try parse(
            "<opml><body><outline \(typeAttr) text=\"X\" xmlUrl=\"https://e.com/f\"/></body></opml>")
        #expect(result.count == (accepted ? 1 : 0))
    }

    @Test func deduplicatesFirstWinsKeepingOrder() throws {
        let result = try parse(
            """
            <opml><body>
              <outline text="B" xmlUrl="https://e.com/b"/>
              <outline text="A" xmlUrl="https://e.com/a"/>
              <outline text="B again" xmlUrl="https://e.com/b"/>
            </body></opml>
            """)
        #expect(result.map(\.title) == ["B", "A"])
    }

    @Test func deepNesting() throws {
        let result = try parse(
            """
            <opml><body><outline text="1"><outline text="2"><outline text="3">
              <outline text="Deep" xmlUrl="https://e.com/deep"/>
            </outline></outline></outline></body></opml>
            """)
        #expect(result.map(\.title) == ["Deep"])
    }

    @Test func outlineWithFeedKeepsFeedChildrenButNotEpisodes() throws {
        let result = try parse(
            """
            <opml><body>
              <outline text="Show" xmlUrl="https://e.com/show">
                <outline type="podcastEpisode" text="Ep" xmlUrl="https://e.com/ep"/>
                <outline text="Odd child" xmlUrl="https://e.com/odd"/>
              </outline>
            </body></opml>
            """)
        #expect(result.map(\.title) == ["Show", "Odd child"])
    }
}
