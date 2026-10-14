import Foundation
import Synchronization

/// Serves canned HTTP responses to a `URLSession` built with `StubURLProtocol.session()`.
/// Every session gets its own route table, so parallel tests do not interfere.
/// `@unchecked`: a delayed response answers from another queue; its own state is in a `Mutex`.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable {
        var status: Int = 200
        var headers: [String: String] = [:]
        var body: Data = Data()
        /// Answer with a redirect to this URL instead (`status` should be 301/302/307/308).
        var redirect: URL?
        /// Answer only after this delay (a slow server); cancelling the task stops waiting.
        var delay: Duration?
    }

    /// Route table: URL → response. `requests` records every request in order.
    final class Routes: Sendable {
        private let state = Mutex((responses: [URL: Response](), requests: [URLRequest]()))

        func set(_ url: URL, _ response: Response) { state.withLock { $0.responses[url] = response } }
        func response(for url: URL) -> Response? { state.withLock { $0.responses[url] } }
        var requests: [URLRequest] { state.withLock { $0.requests } }
        func record(_ request: URLRequest) { state.withLock { $0.requests.append(request) } }
    }

    private static let tables = Mutex([String: Routes]())
    /// The task was cancelled while a delayed response was pending.
    private let isStopped = Mutex(false)
    private static let headerName = "X-Stub-Table"

    /// A session whose requests are answered from `routes`.
    static func session(routes: Routes) -> URLSession {
        URLSession(configuration: configuration(routes: routes))
    }

    /// A configuration whose sessions are answered from `routes` (e.g. for a `Downloader`).
    static func configuration(routes: Routes) -> URLSessionConfiguration {
        let id = UUID().uuidString
        tables.withLock { $0[id] = routes }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        configuration.httpAdditionalHeaders = [headerName: id]
        return configuration
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let id = request.value(forHTTPHeaderField: Self.headerName),
              let routes = Self.tables.withLock({ $0[id] }), let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        routes.record(request)
        guard let stub = routes.response(for: url) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        guard let delay = stub.delay else {
            answer(stub, url: url)
            return
        }
        let (seconds, attoseconds) = delay.components
        DispatchQueue.global().asyncAfter(deadline: .now() + Double(seconds) + Double(attoseconds) / 1e18) { [self] in
            guard !isStopped.withLock({ $0 }) else { return }
            answer(stub, url: url)
        }
    }

    private func answer(_ stub: Response, url: URL) {
        var headers = stub.headers
        if let redirect = stub.redirect { headers["Location"] = redirect.absoluteString }
        let response = HTTPURLResponse(url: url, statusCode: stub.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        if let redirect = stub.redirect {
            var next = URLRequest(url: redirect)
            next.allHTTPHeaderFields = request.allHTTPHeaderFields
            client?.urlProtocol(self, wasRedirectedTo: next, redirectResponse: response)
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        isStopped.withLock { $0 = true }
    }
}
