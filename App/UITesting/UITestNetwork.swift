import Foundation

/// Offline network for UI tests (`-uiTesting`, concept §9): feeds and directory search
/// are answered from canned responses, so the tests run deterministically.
nonisolated final class UITestNetwork: URLProtocol {
    static let feedURL = URL(string: "https://uitest.example.com/feed.xml")!

    static func session() -> URLSession {
        URLSession(configuration: configuration())
    }

    /// Also for the downloader: episode files come from here too.
    static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UITestNetwork.self]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url, let body = Self.body(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(for url: URL) -> Data? {
        if url.host == "itunes.apple.com" { return Data(searchResponse.utf8) }
        if url == feedURL { return Data(feed.utf8) }
        // Episode files (downloads): a few bytes of "audio".
        if url.pathExtension == "mp3" { return Data(repeating: 0, count: 64_000) }
        return nil
    }

    private static let searchResponse = """
        {"resultCount":1,"results":[{"collectionId":42,"collectionName":"Offline Radio",
        "artistName":"Podlist Tests","feedUrl":"\(feedURL.absoluteString)","genres":["News","Podcasts"]}]}
        """

    private static let feed = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel>
        <title>Offline Radio</title><itunes:author>Podlist Tests</itunes:author><itunes:category text="Technology"/>
        <description>A feed that only exists in UI tests.</description>
        <item><guid>offline-2</guid><title>Offline Episode 2</title><pubDate>Tue, 06 Oct 2026 08:00:00 +0000</pubDate>
        <itunes:duration>25:00</itunes:duration><description><![CDATA[<p>Second <b>episode</b>.</p>]]></description>
        <enclosure url="https://uitest.example.com/2.mp3" length="1000" type="audio/mpeg"/></item>
        <item><guid>offline-1</guid><title>Offline Episode 1</title><pubDate>Mon, 05 Oct 2026 08:00:00 +0000</pubDate>
        <itunes:duration>20:00</itunes:duration><description>First episode.</description>
        <enclosure url="https://uitest.example.com/1.mp3" length="1000" type="audio/mpeg"/></item>
        </channel></rss>
        """
}
