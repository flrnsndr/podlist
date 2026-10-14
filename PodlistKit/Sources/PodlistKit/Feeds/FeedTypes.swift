import Foundation

// Shared value types of the feed layer (concept §6.1 "Data"). Parsers produce them,
// services turn them into SwiftData models. All of them cross actor boundaries.

/// A podcast feed (RSS 2.0 with the `itunes`, `podcast`, `psc` and `content` namespaces)
/// as the parser read it. Values are trimmed; empty strings become `nil`.
public struct ParsedFeed: Hashable, Sendable {
    public var title: String
    /// `itunes:author`, falling back to `author` / `managingEditor`.
    public var author: String?
    /// `itunes:summary`, falling back to the channel `description` (may contain HTML).
    public var summary: String?
    /// `itunes:image href`, falling back to `image/url`.
    public var artworkURL: URL?
    /// Channel `link` (the podcast's website).
    public var link: URL?
    /// `itunes:category text` values, top level and subcategories, document order, no duplicates.
    public var categories: [String]
    /// `itunes:new-feed-url`: the publisher moved the feed.
    public var newFeedURL: URL?
    /// Items with an enclosure URL (audio or video), in feed order.
    public var episodes: [ParsedEpisode]

    public init(
        title: String, author: String? = nil, summary: String? = nil, artworkURL: URL? = nil, link: URL? = nil,
        categories: [String] = [], newFeedURL: URL? = nil, episodes: [ParsedEpisode] = []
    ) {
        self.title = title
        self.author = author
        self.summary = summary
        self.artworkURL = artworkURL
        self.link = link
        self.categories = categories
        self.newFeedURL = newFeedURL
        self.episodes = episodes
    }
}

public struct ParsedEpisode: Hashable, Sendable {
    /// `guid`; `nil` if missing or empty (identity falls back to the audio URL).
    public var guid: String?
    public var title: String
    /// HTML: `content:encoded`, falling back to `description`, then `itunes:summary`.
    public var showNotes: String?
    /// `itunes:subtitle` as plain text (concept §4.12, N83); `nil` if missing or empty.
    public var subtitle: String?
    /// `pubDate`; `nil` if missing or unparseable.
    public var publishedAt: Date?
    /// `itunes:duration` in seconds (`HH:MM:SS`, `MM:SS` or seconds).
    public var duration: TimeInterval?
    /// `enclosure url`.
    public var audioURL: URL
    /// `enclosure length`; `nil` if missing or 0.
    public var fileSize: Int64?
    /// `enclosure type`.
    public var mimeType: String?
    /// `itunes:image href` of the item.
    public var imageURL: URL?
    /// `itunes:episode`.
    public var episodeNumber: Int?
    /// `itunes:season`.
    public var seasonNumber: Int?
    /// `podcast:chapters url` (JSON chapters, loaded later).
    public var chaptersURL: URL?
    /// `psc:chapters` (Podlove Simple Chapters), sorted by start; `end` = next start.
    public var chapters: [Chapter]

    public init(
        guid: String? = nil, title: String, showNotes: String? = nil, subtitle: String? = nil, publishedAt: Date? = nil,
        duration: TimeInterval? = nil, audioURL: URL, fileSize: Int64? = nil, mimeType: String? = nil,
        imageURL: URL? = nil, episodeNumber: Int? = nil, seasonNumber: Int? = nil, chaptersURL: URL? = nil,
        chapters: [Chapter] = []
    ) {
        self.guid = guid
        self.title = title
        self.showNotes = showNotes
        self.subtitle = subtitle
        self.publishedAt = publishedAt
        self.duration = duration
        self.audioURL = audioURL
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.imageURL = imageURL
        self.episodeNumber = episodeNumber
        self.seasonNumber = seasonNumber
        self.chaptersURL = chaptersURL
        self.chapters = chapters
    }
}

public enum FeedParserError: Error, Hashable, Sendable {
    /// Well-formed XML, but no RSS `channel` (e.g. an HTML page or an Atom feed).
    case notAFeed
    /// The XML parser failed; the message is for logs only.
    case malformed(String)
}

/// A podcast from an OPML file (import from Pocket Casts, Overcast, …).
public struct OPMLOutline: Hashable, Sendable {
    /// `text`, falling back to `title`.
    public var title: String?
    /// `xmlUrl`.
    public var feedURL: URL

    public init(title: String?, feedURL: URL) {
        self.title = title
        self.feedURL = feedURL
    }
}

public enum OPMLParserError: Error, Hashable, Sendable {
    case notOPML
    case malformed(String)
}

/// A podcast found by the directory search (iTunes Search API).
public struct PodcastSearchResult: Hashable, Sendable, Identifiable {
    /// `collectionId`.
    public var id: Int
    /// `collectionName`.
    public var title: String
    /// `artistName`.
    public var author: String?
    /// `feedUrl`.
    public var feedURL: URL
    /// `artworkUrl600`, falling back to `artworkUrl100`.
    public var artworkURL: URL?
    /// `genres` without the generic "Podcasts".
    public var genres: [String]

    public init(id: Int, title: String, author: String?, feedURL: URL, artworkURL: URL?, genres: [String]) {
        self.id = id
        self.title = title
        self.author = author
        self.feedURL = feedURL
        self.artworkURL = artworkURL
        self.genres = genres
    }
}
