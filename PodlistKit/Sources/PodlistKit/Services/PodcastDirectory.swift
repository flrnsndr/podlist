import Foundation

/// Podcast search in the iTunes directory (concept §7: free, no key).
public struct PodcastDirectory: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// `country`: ISO region code, e.g. "DE"; results follow the store of that country.
    public func search(_ term: String, country: String) async throws -> [PodcastSearchResult] {
        let request = URLRequest(url: ITunesSearch.searchURL(term: term, country: country), timeoutInterval: 20)
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FeedLoadError.http(status: http.statusCode)
        }
        return try ITunesSearch.decode(data)
    }
}
