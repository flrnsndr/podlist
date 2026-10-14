import Foundation
import Testing
@testable import PodlistKit

struct FeedLoaderTests {
    private let routes = StubURLProtocol.Routes()
    private var loader: FeedLoader { FeedLoader(session: StubURLProtocol.session(routes: routes)) }
    private let feed = URL(string: "https://example.com/feed.xml")!
    private let body = Data("<rss/>".utf8)

    @Test func loadsAndReturnsValidators() async throws {
        routes.set(feed, .init(headers: ["ETag": "\"v1\"", "Last-Modified": "Tue, 06 Oct 2026 10:00:00 GMT"], body: body))
        let result = try await loader.load(feed)
        #expect(result == .loaded(data: body, etag: "\"v1\"", lastModified: "Tue, 06 Oct 2026 10:00:00 GMT", movedTo: nil))
    }

    @Test func sendsConditionalHeadersAndHandlesNotModified() async throws {
        routes.set(feed, .init(status: 304))
        let result = try await loader.load(feed, etag: "\"v1\"", lastModified: "yesterday")
        #expect(result == .notModified)
        let request = try #require(routes.requests.first)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == "yesterday")
    }

    @Test(arguments: [
        ([301], true), ([308], true), ([301, 308], true), ([302], false), ([307], false), ([301, 302], false),
    ])
    func reportsOnlyPermanentRedirects(statuses: [Int], permanent: Bool) async throws {
        var current = feed
        for (index, status) in statuses.enumerated() {
            let next = URL(string: "https://new\(index).example.com/feed.xml")!
            routes.set(current, .init(status: status, redirect: next))
            current = next
        }
        routes.set(current, .init(body: body))
        let result = try await loader.load(feed)
        #expect(result == .loaded(data: body, etag: nil, lastModified: nil, movedTo: permanent ? current : nil))
    }

    @Test func httpErrorsThrow() async {
        routes.set(feed, .init(status: 404))
        await #expect(throws: FeedLoadError.http(status: 404)) { try await loader.load(feed) }
    }

    @Test(arguments: [
        ("https://example.com/feed", "https://example.com/feed"),
        ("http://example.com/feed?x=1", "https://example.com/feed?x=1"),
        ("feed://example.com/rss", "https://example.com/rss"),
        ("feed:https://example.com/rss", "https://example.com/rss"),
        ("itpc://example.com/rss", "https://example.com/rss"),
        ("pcast://example.com/rss", "https://example.com/rss"),
    ])
    func normalizesFeedURLs(input: String, expected: String) {
        #expect(FeedLoader.normalizedFeedURL(URL(string: input)!) == URL(string: expected)!)
    }

    @Test(arguments: ["ftp://example.com/feed", "mailto:a@example.com", "https:///feed", "file:///tmp/feed.xml"])
    func rejectsNonFeedURLs(input: String) {
        #expect(FeedLoader.normalizedFeedURL(URL(string: input)!) == nil)
    }
}
