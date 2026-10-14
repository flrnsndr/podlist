import Foundation
import Testing

@testable import PodlistKit

struct ITunesSearchTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures/Search"))
        return try Data(contentsOf: url)
    }

    private func items(_ url: URL) throws -> [String: String] {
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    @Test func urlBasics() throws {
        let url = ITunesSearch.searchURL(term: "lage", country: "DE")
        #expect(url.scheme == "https")
        #expect(url.host == "itunes.apple.com")
        #expect(url.path == "/search")
        let q = try items(url)
        #expect(q["media"] == "podcast")
        #expect(q["entity"] == "podcast")
        #expect(q["term"] == "lage")
        #expect(q["country"] == "DE")
        #expect(q["limit"] == "25")
    }

    @Test func customLimit() throws {
        #expect(try items(ITunesSearch.searchURL(term: "x", country: "US", limit: 5))["limit"] == "5")
    }

    @Test(arguments: [
        ("Fußball Müller", "Fu%C3%9Fball%20M%C3%BCller"),
        ("a&b", "a%26b"),
        ("c++", "c%2B%2B"),
        ("two words", "two%20words"),
        ("a=b#c?d/e", "a%3Db%23c%3Fd%2Fe"),
    ])
    func termIsPercentEncoded(_ term: String, _ encoded: String) throws {
        let url = ITunesSearch.searchURL(term: term, country: "DE")
        #expect(url.absoluteString.contains("term=\(encoded)"))
        #expect(try items(url)["term"] == term)
    }

    @Test func decodesFixture() throws {
        let results = try ITunesSearch.decode(fixture("search-response"))
        #expect(results.map(\.id) == [1419222111, 1200361736, 1000])
        let first = results[0]
        #expect(first.title == "Lage der Nation")
        #expect(first.author == "Philip Banse & Ulf Buermeyer")
        #expect(first.feedURL.absoluteString == "https://feeds.lagedernation.org/feed.xml")
        #expect(first.artworkURL?.absoluteString == "https://is1-ssl.mzstatic.com/image/thumb/600x600bb.jpg")
        #expect(first.genres == ["Nachrichten"])
    }

    @Test func artworkFallsBackTo100() throws {
        let results = try ITunesSearch.decode(fixture("search-response"))
        #expect(results[1].artworkURL?.absoluteString == "https://is1-ssl.mzstatic.com/image/thumb/radiolab100x100bb.jpg")
        #expect(results[1].genres == ["Wissenschaft", "Natur"])
    }

    @Test func missingOptionalsAreNil() throws {
        let last = try #require(try ITunesSearch.decode(fixture("search-response")).last)
        #expect(last.author == nil)
        #expect(last.artworkURL == nil)
        #expect(last.genres.isEmpty)
    }

    @Test func emptyResults() throws {
        #expect(try ITunesSearch.decode(fixture("search-empty")).isEmpty)
    }

    @Test(arguments: [
        #""feedUrl": "ftp://e.com/f""#,
        #""feedUrl": "not a url""#,
        #""feedUrl": """#,
        #""feedUrl": null"#,
    ])
    func invalidFeedURLIsDropped(_ feedField: String) throws {
        let json = #"{"resultCount":1,"results":[{"collectionId":1,"collectionName":"X",\#(feedField)}]}"#
        #expect(try ITunesSearch.decode(Data(json.utf8)).isEmpty)
    }

    @Test(arguments: ["", "{", "[]", #"{"results":"x"}"#])
    func garbageThrows(_ text: String) {
        #expect(throws: (any Error).self) { try ITunesSearch.decode(Data(text.utf8)) }
    }
}
