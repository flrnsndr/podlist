import Foundation

/// Request and response handling for the iTunes Search API (podcast directory search).
public enum ITunesSearch {
    /// `https://itunes.apple.com/search?media=podcast&entity=podcast&term=…&country=…&limit=…`
    public static func searchURL(term: String, country: String, limit: Int = 25) -> URL {
        let query = [
            ("media", "podcast"), ("entity", "podcast"), ("term", term), ("country", country),
            ("limit", String(limit)),
        ]
        .map { "\($0.0)=\(encode($0.1))" }
        .joined(separator: "&")
        // The query only contains unreserved characters and percent escapes, so this cannot fail.
        return URL(string: "https://itunes.apple.com/search?\(query)")!
    }

    /// Decodes the `{"resultCount":…,"results":[…]}` response. Results without a valid
    /// http(s) `feedUrl` (or without `collectionId`) are dropped.
    public static func decode(_ data: Data) throws -> [PodcastSearchResult] {
        let response = try JSONDecoder().decode(Response.self, from: data)
        return response.results.compactMap { $0.value?.result }
    }

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    private struct Response: Decodable {
        let results: [Lossy<Entry>]
    }

    /// Decodes an element or yields `nil` instead of failing the whole array.
    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
        }
    }

    private struct Entry: Decodable {
        let collectionId: Int?
        let collectionName: String?
        let artistName: String?
        let feedUrl: String?
        let artworkUrl600: String?
        let artworkUrl100: String?
        let genres: [String]?

        var result: PodcastSearchResult? {
            guard let collectionId, let feedURL = Self.webURL(feedUrl) else { return nil }
            let name = collectionName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let author = artistName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return PodcastSearchResult(
                id: collectionId,
                title: name,
                author: author?.isEmpty == false ? author : nil,
                feedURL: feedURL,
                artworkURL: Self.webURL(artworkUrl600) ?? Self.webURL(artworkUrl100),
                genres: (genres ?? []).filter { $0 != "Podcasts" })
        }

        private static func webURL(_ value: String?) -> URL? {
            guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty,
                let url = URL(string: trimmed),
                let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
                let host = url.host(percentEncoded: false), !host.isEmpty
            else { return nil }
            return url
        }
    }
}
