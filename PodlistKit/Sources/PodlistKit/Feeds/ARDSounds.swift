import Foundation

public enum ARDSoundsError: Error, Hashable, Sendable {
    /// The show or episode does not exist (any more).
    case notFound
    /// The API answered with errors or something that is no answer to the query.
    case malformed
}

/// ARD Sounds (formerly ARD Audiothek) as a podcast source for shows without an RSS feed
/// (concept §4.13). Pure: links, the GraphQL queries, and the mapping of the answers to the
/// feed layer's values. A show maps to the same `ParsedFeed` the `FeedParser` produces, so
/// everything downstream treats it like any other podcast.
///
/// An ARD-backed podcast is stored with its canonical show page as the feed URL
/// (`showURL(_:)`); the `FeedLoader` recognizes it and asks the API instead.
public enum ARDSounds {
    /// A show or an episode, by its URN (`urn:ard:show:<hex>`, `urn:ard:episode:<hex>`).
    public enum Reference: Hashable, Sendable {
        case show(String)
        case episode(String)

        /// The canonical page on ardsounds.de.
        public var url: URL {
            switch self {
            case .show(let urn): ARDSounds.showURL(urn)
            case .episode(let urn): URL(string: "https://www.ardsounds.de/episode/\(urn)/")!
            }
        }
    }

    /// A show found by the search.
    public struct Show: Hashable, Sendable {
        public var urn: String
        public var title: String
        /// `publicationService.organizationName`, e.g. "WDR".
        public var broadcaster: String?
        /// The broadcaster's own RSS feed, if ARD knows a usable one (`feedUrl` is often
        /// missing or a `crid://` value).
        public var feedURL: URL?
        public var artworkURL: URL?

        public init(urn: String, title: String, broadcaster: String?, feedURL: URL?, artworkURL: URL?) {
            self.urn = urn
            self.title = title
            self.broadcaster = broadcaster
            self.feedURL = feedURL
            self.artworkURL = artworkURL
        }
    }

    /// A show as loaded: the feed and the stand-in for HTTP validators (`stateQueryURL`).
    public struct LoadedShow: Hashable, Sendable {
        public var feed: ParsedFeed
        /// Changes whenever an episode is added, changed or removed; `nil` if ARD says nothing.
        public var validator: String?
    }

    // MARK: Links

    private static let hosts: Set<String> = ["ardsounds.de", "www.ardsounds.de", "ardaudiothek.de", "www.ardaudiothek.de"]

    /// Recognizes show and episode pages of ardsounds.de and ardaudiothek.de and bare URNs.
    public static func reference(from text: String) -> Reference? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: text).flatMap(reference(from:))
    }

    public static func reference(from url: URL) -> Reference? {
        switch url.scheme?.lowercased() {
        case "urn":
            // A bare URN is nothing but the URN.
            let text = url.absoluteString.lowercased()
            guard let reference = reference(inPath: text) else { return nil }
            switch reference {
            case .show(let urn), .episode(let urn): return urn == text ? reference : nil
            }
        case "http", "https":
            guard let host = url.host(percentEncoded: false)?.lowercased(), hosts.contains(host) else { return nil }
            return reference(inPath: url.path(percentEncoded: false))
        default:
            return nil
        }
    }

    /// The canonical page of a show: the feed URL an ARD-backed podcast is stored with.
    public static func showURL(_ urn: String) -> URL {
        URL(string: "https://www.ardsounds.de/sendung/\(urn)/")!
    }

    /// The first `urn:ard:show:<hex>` / `urn:ard:episode:<hex>` in `text`.
    private static func reference(inPath text: String) -> Reference? {
        let lowered = text.lowercased()
        for (kind, make) in [("show", Reference.show), ("episode", Reference.episode)] {
            let prefix = "urn:ard:\(kind):"
            guard let range = lowered.range(of: prefix) else { continue }
            let hex = lowered[range.upperBound...].prefix { $0.isHexDigit }
            guard (8...32).contains(hex.count) else { return nil }
            return make(prefix + hex)
        }
        return nil
    }

    // MARK: Queries

    private static let endpoint = "https://api.ardaudiothek.de/graphql"
    /// More than any show has (the longest seen: ~900).
    static let maxEpisodes = 1000
    private static let state = "lastItemModified lastItemAdded numberOfElements"
    private static let image = "image { url url1X1 }"

    /// The show with all its published episodes, newest first.
    public static func showQueryURL(_ urn: String) -> URL {
        queryURL("""
            { programSet(id: \(literal(urn))) { coreId title synopsis sharingUrl \(state) \(image) \
            publicationService { title organizationName } \
            items(first: \(maxEpisodes), orderBy: PUBLISH_DATE_DESC, filter: { isPublished: { equalTo: true } }) \
            { nodes { coreId title summary synopsis description publishDate duration \(image) audios { url mimeType } } } } }
            """)
    }

    /// Only what tells whether the show changed (a refresh loads the show only then).
    public static func stateQueryURL(_ urn: String) -> URL {
        queryURL("{ programSet(id: \(literal(urn))) { \(state) } }")
    }

    /// The show an episode belongs to (a pasted episode link).
    public static func episodeQueryURL(_ urn: String) -> URL {
        queryURL("{ item(id: \(literal(urn))) { programSet { coreId } } }")
    }

    public static func searchQueryURL(term: String, limit: Int = 10) -> URL {
        queryURL("""
            { search(query: \(literal(term)), limit: \(limit)) { programSets { nodes { coreId title feedUrl \
            numberOfElements \(image) publicationService { organizationName } } } } }
            """)
    }

    /// GET, so that each query has its own URL.
    private static func queryURL(_ query: String) -> URL {
        var components = URLComponents(string: endpoint)!
        components.queryItems = [URLQueryItem(name: "query", value: query)]
        // `+` would read as a space on the server.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }

    /// A GraphQL string literal.
    private static func literal(_ text: String) -> String {
        var escaped = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n", "\r", "\t": escaped += " "
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"\(escaped)\""
    }

    // MARK: Decoding

    public static func decodeShow(_ data: Data) throws -> LoadedShow {
        let set = try decode(ShowData.self, from: data).programSet
        guard let set else { throw ARDSoundsError.notFound }
        guard let urn = set.coreId.flatMap(showURN) else { throw ARDSoundsError.malformed }
        let feed = ParsedFeed(
            title: trimmed(set.title) ?? "",
            author: trimmed(set.publicationService?.organizationName),
            summary: trimmed(set.synopsis),
            artworkURL: imageURL(set.image, width: 1400),
            link: FeedParser.parseWebURL(set.sharingUrl) ?? showURL(urn),
            episodes: (set.items?.nodes ?? []).compactMap { $0.value?.episode })
        return LoadedShow(feed: feed, validator: set.validator)
    }

    public static func decodeState(_ data: Data) throws -> String? {
        guard let set = try decode(ShowData.self, from: data).programSet else { throw ARDSoundsError.notFound }
        return set.validator
    }

    public static func decodeShowURN(ofEpisode data: Data) throws -> String {
        guard let item = try decode(ItemData.self, from: data).item else { throw ARDSoundsError.notFound }
        guard let urn = item.programSet?.coreId.flatMap(showURN) else { throw ARDSoundsError.malformed }
        return urn
    }

    /// Shows only (no collections), without empty ones.
    public static func decodeSearch(_ data: Data) throws -> [Show] {
        let nodes = try decode(SearchData.self, from: data).search?.programSets?.nodes ?? []
        return nodes.compactMap { node -> Show? in
            guard let node = node.value, let urn = node.coreId.flatMap(showURN), let title = trimmed(node.title),
                  node.numberOfElements != 0
            else { return nil }
            return Show(
                urn: urn, title: title, broadcaster: trimmed(node.publicationService?.organizationName),
                feedURL: FeedParser.parseWebURL(node.feedUrl).flatMap(FeedLoader.normalizedFeedURL),
                artworkURL: imageURL(node.image, width: 600))
        }
    }

    private static func showURN(_ coreID: String) -> String? {
        guard case .show(let urn) = reference(inPath: coreID) else { return nil }
        return urn
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        let response: Response<Value>
        do {
            response = try JSONDecoder().decode(Response<Value>.self, from: data)
        } catch {
            throw ARDSoundsError.malformed
        }
        guard let value = response.data, response.errors?.isEmpty != false else { throw ARDSoundsError.malformed }
        return value
    }

    /// ARD's image URLs are templates: `…?w={width}&ch=…`.
    private static func imageURL(_ image: Image?, width: Int) -> URL? {
        let template = trimmed(image?.url1X1) ?? trimmed(image?.url)
        return FeedParser.parseWebURL(template?.replacingOccurrences(of: "{width}", with: String(width)))
    }

    static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    // MARK: Response types

    private struct Response<Value: Decodable>: Decodable {
        let data: Value?
        let errors: [Lossy<GraphQLError>]?
    }

    private struct GraphQLError: Decodable {
        let message: String?
    }

    private struct ShowData: Decodable {
        let programSet: ProgramSet?
    }

    private struct ItemData: Decodable {
        struct Item: Decodable {
            struct ProgramSet: Decodable { let coreId: String? }
            let programSet: ProgramSet?
        }
        let item: Item?
    }

    private struct SearchData: Decodable {
        struct Search: Decodable {
            struct ProgramSets: Decodable { let nodes: [Lossy<ProgramSet>]? }
            let programSets: ProgramSets?
        }
        let search: Search?
    }

    private struct Image: Decodable {
        let url: String?
        let url1X1: String?
    }

    private struct PublicationService: Decodable {
        let organizationName: String?
    }

    private struct ProgramSet: Decodable {
        struct Items: Decodable { let nodes: [Lossy<Item>]? }
        let coreId: String?
        let title: String?
        let synopsis: String?
        let sharingUrl: String?
        let feedUrl: String?
        let numberOfElements: Int?
        let lastItemAdded: String?
        let lastItemModified: String?
        let image: Image?
        let publicationService: PublicationService?
        let items: Items?

        var validator: String? {
            guard lastItemModified != nil || lastItemAdded != nil || numberOfElements != nil else { return nil }
            return [lastItemModified ?? "-", lastItemAdded ?? "-", numberOfElements.map(String.init) ?? "-"].joined(separator: "|")
        }
    }

    private struct Item: Decodable {
        struct Audio: Decodable {
            let url: String?
            let mimeType: String?
        }
        let coreId: String?
        let title: String?
        let summary: String?
        let synopsis: String?
        let description: String?
        let publishDate: String?
        let duration: Double?
        let image: Image?
        let audios: [Lossy<Audio>]?

        var episode: ParsedEpisode? {
            let audios = (audios ?? []).compactMap(\.value)
            guard let audio = audios.first(where: { FeedParser.parseWebURL($0.url) != nil }),
                  let audioURL = FeedParser.parseWebURL(audio.url)
            else { return nil }
            let description = ARDSounds.trimmed(self.description)
            let summary = ARDSounds.trimmed(self.summary) ?? ARDSounds.trimmed(synopsis)
            return ParsedEpisode(
                guid: ARDSounds.trimmed(coreId),
                title: ARDSounds.trimmed(title) ?? "",
                showNotes: (description ?? summary).map(ARDSounds.html),
                subtitle: ARDSounds.subtitle(summary, description: description),
                publishedAt: publishDate.flatMap(FeedParser.parseDate),
                duration: duration.flatMap { $0 > 0 ? $0 : nil },
                audioURL: audioURL,
                mimeType: ARDSounds.trimmed(audio.mimeType).map { $0 == "audio/mp3" ? "audio/mpeg" : $0 },
                imageURL: ARDSounds.imageURL(image, width: 1400))
        }
    }

    /// Decodes an element or yields `nil` instead of failing the whole array.
    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
        }
    }

    // MARK: Text

    /// The summary, unless it is only the start of the description (it often is, cut off with "…").
    private static func subtitle(_ summary: String?, description: String?) -> String? {
        guard let summary else { return nil }
        guard let description else { return summary }
        var start = summary
        while let last = start.last, last == "." || last == "…" || last.isWhitespace { start.removeLast() }
        return normalizedLines(description).hasPrefix(normalizedLines(start)) ? nil : normalizedLines(summary)
    }

    /// ARD's texts are plain text with line breaks; show notes are HTML.
    static func html(_ text: String) -> String {
        let escaped = normalizedLines(text)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return escaped.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "<p>\($0.replacingOccurrences(of: "\n", with: "<br>"))</p>" }
            .joined()
    }

    private static func normalizedLines(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
