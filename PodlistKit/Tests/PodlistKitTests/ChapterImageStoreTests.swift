import Foundation
import Testing
@testable import PodlistKit

struct ChapterImageStoreTests {
    private let routes = StubURLProtocol.Routes()
    private var store: ChapterImageStore {
        ChapterImageStore(
            directory: URL.temporaryDirectory.appending(path: "ChapterImageStoreTests-\(UUID().uuidString)"),
            session: StubURLProtocol.session(routes: routes))
    }
    private let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0])

    /// App Transport Security blocks plain `http` (e.g. the artwork of "Bits und so").
    @Test func loadsHTTPArtworkOverHTTPS() async throws {
        routes.set(URL(string: "https://example.com/art.jpg")!, .init(body: jpeg))
        let data = await store.imageData(for: URL(string: "http://example.com/art.jpg")!)
        #expect(data == jpeg)
        #expect(routes.requests.map(\.url?.absoluteString) == ["https://example.com/art.jpg"])
    }

    @Test func loadsHTTPSArtworkUnchanged() async throws {
        let url = URL(string: "https://example.com/art.jpg?size=600")!
        routes.set(url, .init(body: jpeg))
        #expect(await store.imageData(for: url) == jpeg)
        #expect(routes.requests.map(\.url) == [url])
    }

    @Test(arguments: [
        ("http://example.com/a.jpg", "https://example.com/a.jpg"),
        ("HTTP://example.com:8080/a.jpg?x=1", "https://example.com:8080/a.jpg?x=1"),
        ("https://example.com/a.jpg", "https://example.com/a.jpg"),
        ("podlist-chapter-image:abc-1", "podlist-chapter-image:abc-1"),
    ])
    func secureURL(raw: String, expected: String) {
        #expect(ChapterImageStore.secureURL(URL(string: raw)!).absoluteString == expected)
    }
}
