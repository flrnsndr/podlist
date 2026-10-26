import Foundation
import Synchronization

public enum FeedLoadError: Error, Hashable, Sendable {
    case http(status: Int)
    case notHTTP
}

/// Loads feeds with conditional requests (ETag / Last-Modified) and reports permanent
/// redirects, so the stored feed URL can follow a moved feed (concept §8).
public struct FeedLoader: Sendable {
    public enum Result: Sendable, Equatable {
        case notModified
        /// `movedTo`: the final URL if every redirect on the way was permanent (301/308).
        case loaded(data: Data, etag: String?, lastModified: String?, movedTo: URL?)
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// ARD Sounds over the same session (feed URLs of ARD-backed podcasts, concept §4.13).
    public var ard: ARDSoundsClient { ARDSoundsClient(session: session) }

    /// Feeds over plain `http` are loaded via `https` (App Transport Security); `feed:`,
    /// `itpc:` and `pcast:` links become `https` too. ARD Sounds links and URNs become their
    /// canonical page (`ARDSounds.Reference.url`). Returns `nil` for anything that is no feed URL.
    public static func normalizedFeedURL(_ url: URL) -> URL? {
        if let reference = ARDSounds.reference(from: url) { return reference.url }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else { return nil }
        switch scheme {
        case "https": break
        case "http", "feed", "itpc", "pcast", "podcast":
            // "feed://example.com/rss" and "feed:https://example.com/rss" both occur.
            if components.host == nil, let inner = URL(string: components.path), inner.scheme != nil {
                return normalizedFeedURL(inner)
            }
            components.scheme = "https"
        default: return nil
        }
        guard components.host?.isEmpty == false else { return nil }
        return components.url
    }

    public func load(_ url: URL, etag: String? = nil, lastModified: String? = nil) async throws -> Result {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.setValue("Podlist/1.0", forHTTPHeaderField: "User-Agent")
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }

        let recorder = RedirectRecorder()
        let (data, response) = try await session.data(for: request, delegate: recorder)
        guard let http = response as? HTTPURLResponse else { throw FeedLoadError.notHTTP }
        switch http.statusCode {
        case 304:
            return .notModified
        case 200..<300:
            let movedTo = recorder.isPermanent ? http.url.flatMap { $0 == url ? nil : $0 } : nil
            return .loaded(
                data: data, etag: http.value(forHTTPHeaderField: "ETag"),
                lastModified: http.value(forHTTPHeaderField: "Last-Modified"), movedTo: movedTo)
        default:
            throw FeedLoadError.http(status: http.statusCode)
        }
    }
}

/// Remembers whether all redirects of a request were permanent.
private final class RedirectRecorder: NSObject, URLSessionTaskDelegate, Sendable {
    private let state = Mutex((redirects: 0, allPermanent: true))

    var isPermanent: Bool { state.withLock { $0.redirects > 0 && $0.allPermanent } }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        state.withLock {
            $0.redirects += 1
            if ![301, 308].contains(response.statusCode) { $0.allPermanent = false }
        }
        return request
    }
}
