import Foundation

/// Talks to ARD's GraphQL API (open, no key; concept §4.13). Unofficial: if ARD changes it,
/// ARD-backed podcasts fail to refresh like a dead feed, and the search shows iTunes only.
public struct ARDSoundsClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// The show `reference` points at; an episode is asked for its show.
    public func showURN(for reference: ARDSounds.Reference) async throws -> String {
        switch reference {
        case .show(let urn): urn
        case .episode(let urn): try ARDSounds.decodeShowURN(ofEpisode: try await get(ARDSounds.episodeQueryURL(urn)))
        }
    }

    public func show(_ urn: String) async throws -> ARDSounds.LoadedShow {
        try ARDSounds.decodeShow(try await get(ARDSounds.showQueryURL(urn), timeout: 60))
    }

    /// The show's validator (`ARDSounds.LoadedShow.validator`), cheap.
    public func state(of urn: String) async throws -> String? {
        try ARDSounds.decodeState(try await get(ARDSounds.stateQueryURL(urn)))
    }

    public func search(_ term: String, timeout: TimeInterval = 10) async throws -> [ARDSounds.Show] {
        try ARDSounds.decodeSearch(try await get(ARDSounds.searchQueryURL(term: term), timeout: timeout))
    }

    private func get(_ url: URL, timeout: TimeInterval = 30) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.setValue("Podlist/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedLoadError.notHTTP }
        guard (200..<300).contains(http.statusCode) else { throw FeedLoadError.http(status: http.statusCode) }
        return data
    }
}
