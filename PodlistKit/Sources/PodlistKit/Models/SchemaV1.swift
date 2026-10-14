import Foundation
import SwiftData

// SwiftData schema, version 1 (concept §5). Frozen: Florian's device has a store in this
// version; changes go into a new `VersionedSchema` (see SchemaV6: copy the current one,
// move the typealiases and add a migration stage). CloudKit-compatible from day one:
// every relationship is optional and has an inverse, every attribute has a default,
// no unique constraints, no `.deny` delete rule. Enums are stored as `…Raw: String`
// with typed accessors; ordering always via `position: Double`.

/// Placeholder for non-optional URL attributes (CloudKit needs a default value).
let placeholderURL = URL(string: "about:blank")!

public enum SchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [Podcast.self, Episode.self, Playlist.self, PlaylistAssignment.self, PlaylistEntry.self,
         QueueItem.self, UpNextSnapshot.self]
    }

    @Model public final class Podcast {
        /// Stable ID for history, notifications, deep links and sync.
        public var uuid: UUID = UUID()
        public var feedURL: URL = placeholderURL
        public var title: String = ""
        public var author: String?
        public var summary: String?
        public var artworkURL: URL?
        /// The podcast's website.
        public var link: URL?
        /// From `itunes:category`; used to suggest playlists.
        public var categories: [String] = []
        public var subscribedAt: Date = Date.distantPast
        public var lastRefreshedAt: Date?
        public var etag: String?
        public var lastModified: String?
        /// `false` = unsubscribed but still referenced (concept §4.9).
        public var isSubscribed: Bool = true
        public var notificationsEnabled: Bool = false
        /// `nil` = global speed.
        public var playbackSpeed: Double?
        public var skipIntroSeconds: Int = 0
        public var skipOutroSeconds: Int = 0
        @Relationship(deleteRule: .cascade, inverse: \Episode.podcast)
        public var episodes: [Episode]?
        @Relationship(deleteRule: .cascade, inverse: \PlaylistAssignment.podcast)
        public var assignments: [PlaylistAssignment]?

        public init(feedURL: URL, title: String, subscribedAt: Date) {
            self.feedURL = feedURL
            self.title = title
            self.subscribedAt = subscribedAt
        }
    }

    @Model public final class Episode {
        public var uuid: UUID = UUID()
        /// Identity within the podcast (from the feed).
        public var guid: String = ""
        public var title: String = ""
        /// HTML.
        public var showNotes: String?
        public var publishedAt: Date = Date.distantPast
        /// From the feed; replaced by the real duration after the first load.
        public var duration: TimeInterval?
        public var audioURL: URL = placeholderURL
        public var fileSize: Int64?
        /// Episode artwork; `nil` = the podcast's artwork.
        public var imageURL: URL?
        public var episodeNumber: Int?
        public var seasonNumber: Int?
        public var playbackPosition: TimeInterval = 0
        /// `nil` = unplayed. Global status (concept §4.3).
        public var playedAt: Date?
        public var downloadStateRaw: String = DownloadState.none.rawValue
        public var localFileName: String?
        /// `podcast:chapters`.
        public var chaptersURL: URL?
        /// Resolved chapters from the best source.
        public var chapters: [Chapter] = []
        public var chaptersSourceRaw: String?
        public var podcast: Podcast?
        @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.episode)
        public var playlistEntries: [PlaylistEntry]?
        @Relationship(deleteRule: .cascade, inverse: \QueueItem.episode)
        public var queueItems: [QueueItem]?
        /// Inverse of `Playlist.resumeEpisode` (CloudKit needs every inverse).
        @Relationship(deleteRule: .nullify, inverse: \Playlist.resumeEpisode)
        public var resumingPlaylists: [Playlist]?

        public init(guid: String, title: String, publishedAt: Date, audioURL: URL) {
            self.guid = guid
            self.title = title
            self.publishedAt = publishedAt
            self.audioURL = audioURL
        }

        public var downloadState: DownloadState {
            get { DownloadState(rawValue: downloadStateRaw) ?? .none }
            set { downloadStateRaw = newValue.rawValue }
        }

        public var chaptersSource: ChapterSource? {
            get { chaptersSourceRaw.flatMap(ChapterSource.init(rawValue:)) }
            set { chaptersSourceRaw = newValue?.rawValue }
        }

        public var isPlayed: Bool { playedAt != nil }
    }

    @Model public final class Playlist {
        public var uuid: UUID = UUID()
        /// Default playlists: translated name as long as `customName` is nil (concept §4.8).
        public var systemKey: String?
        public var customName: String?
        /// From a fixed, accessible palette.
        public var colorKey: String = "blue"
        /// SF Symbol, so color is never the only signal.
        public var symbolName: String = "music.note.list"
        public var displayOrder: Double = 0
        public var sortRaw: String = PlaylistSort.manual.rawValue
        public var sortAscending: Bool = true
        public var playedPolicyRaw: String = PlayedPolicy.remove.rawValue
        public var autoDownload: Bool = false
        /// Wiedergabestand / cursor (concept §4.4).
        public var resumeEpisode: Episode?
        @Relationship(deleteRule: .cascade, inverse: \PlaylistEntry.playlist)
        public var entries: [PlaylistEntry]?
        @Relationship(deleteRule: .cascade, inverse: \PlaylistAssignment.playlist)
        public var assignments: [PlaylistAssignment]?
        @Relationship(deleteRule: .cascade, inverse: \QueueItem.playlist)
        public var queueItems: [QueueItem]?

        public init(systemKey: String? = nil, customName: String? = nil, colorKey: String, symbolName: String, displayOrder: Double) {
            self.systemKey = systemKey
            self.customName = customName
            self.colorKey = colorKey
            self.symbolName = symbolName
            self.displayOrder = displayOrder
        }

        public var sort: PlaylistSort {
            get { PlaylistSort(rawValue: sortRaw) ?? .manual }
            set { sortRaw = newValue.rawValue }
        }

        public var playedPolicy: PlayedPolicy {
            get { PlayedPolicy(rawValue: playedPolicyRaw) ?? .remove }
            set { playedPolicyRaw = newValue.rawValue }
        }
    }

    /// The "tag" of a podcast: podcast ↔ playlist with its auto-add rule.
    @Model public final class PlaylistAssignment {
        public var podcast: Podcast?
        public var playlist: Playlist?
        public var autoAddRaw: String = AutoAddRule.bottom.rawValue
        public var createdAt: Date = Date.distantPast

        public init(podcast: Podcast, playlist: Playlist, autoAdd: AutoAddRule, createdAt: Date) {
            self.podcast = podcast
            self.playlist = playlist
            self.autoAddRaw = autoAdd.rawValue
            self.createdAt = createdAt
        }

        public var autoAdd: AutoAddRule {
            get { AutoAddRule(rawValue: autoAddRaw) ?? .off }
            set { autoAddRaw = newValue.rawValue }
        }
    }

    @Model public final class PlaylistEntry {
        public var playlist: Playlist?
        public var episode: Episode?
        public var position: Double = 0
        public var addedAt: Date = Date.distantPast
        public var originRaw: String = EntryOrigin.manual.rawValue

        public init(playlist: Playlist, episode: Episode, position: Double, addedAt: Date, origin: EntryOrigin) {
            self.playlist = playlist
            self.episode = episode
            self.position = position
            self.addedAt = addedAt
            self.originRaw = origin.rawValue
        }

        public var origin: EntryOrigin {
            get { EntryOrigin(rawValue: originRaw) ?? .manual }
            set { originRaw = newValue.rawValue }
        }
    }

    /// Current Up Next, survives app restarts. A regular item has exactly one of `episode` /
    /// `playlist`. The single item with `isNowPlaying` is the episode in the player and the
    /// playlist block it came from (`playlist` optional), see `NowPlaying`.
    @Model public final class QueueItem {
        public var position: Double = 0
        public var isNowPlaying: Bool = false
        public var episode: Episode?
        public var playlist: Playlist?

        public init(position: Double, episode: Episode) {
            self.position = position
            self.episode = episode
        }

        public init(position: Double, playlist: Playlist) {
            self.position = position
            self.playlist = playlist
        }

        public init(nowPlaying episode: Episode, playlist: Playlist? = nil) {
            self.isNowPlaying = true
            self.episode = episode
            self.playlist = playlist
        }
    }

    /// Up Next history entry. `payload` is an encoded `UpNextState` (UUIDs only).
    @Model public final class UpNextSnapshot {
        public var createdAt: Date = Date.distantPast
        public var reasonRaw: String = UpNextSnapshotReason.replaced.rawValue
        public var payload: Data = Data()

        public init(_ value: UpNextSnapshotValue) throws {
            createdAt = value.createdAt
            reasonRaw = value.reason.rawValue
            payload = try JSONEncoder().encode(value.state)
        }

        public func value() throws -> UpNextSnapshotValue {
            UpNextSnapshotValue(
                createdAt: createdAt,
                reason: UpNextSnapshotReason(rawValue: reasonRaw) ?? .replaced,
                state: try JSONDecoder().decode(UpNextState.self, from: payload))
        }
    }
}

public enum DownloadState: String, Sendable, Codable, CaseIterable {
    case none, queued, downloading, downloaded, failed
}

public enum ChapterSource: String, Sendable, Codable, CaseIterable {
    case json, podlove, id3, mp4, shownotes
}

public enum EntryOrigin: String, Sendable, Codable, CaseIterable {
    case automatic, manual
}

/// A chapter mark, stored inline in `Episode.chapters`.
public struct Chapter: Codable, Hashable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval?
    public var title: String
    public var imageURL: URL?
    public var linkURL: URL?
    /// JSON chapters `toc: false`: image and link only, no list entry.
    public var isHidden: Bool

    public init(start: TimeInterval, end: TimeInterval? = nil, title: String, imageURL: URL? = nil, linkURL: URL? = nil, isHidden: Bool = false) {
        self.start = start
        self.end = end
        self.title = title
        self.imageURL = imageURL
        self.linkURL = linkURL
        self.isHidden = isHidden
    }
}
