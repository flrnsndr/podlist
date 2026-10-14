import Foundation

/// An entry of Up Next: a single episode or a live block of a playlist (concept §4.4).
public enum UpNextItem: Hashable, Sendable, Codable {
    case episode(EpisodeID)
    case playlist(PlaylistID)
}

/// The episode that is loaded in the player and the playlist block it came from
/// (`nil` for a single episode).
public struct NowPlaying: Hashable, Sendable, Codable {
    public var episode: EpisodeID
    public var playlist: PlaylistID?

    public init(episode: EpisodeID, playlist: PlaylistID? = nil) {
        self.episode = episode
        self.playlist = playlist
    }
}

/// The complete Up Next state. Playlist cursors (`resumeEpisode`) are not part of it:
/// they belong to the playlists.
public struct UpNextState: Hashable, Sendable, Codable {
    public var nowPlaying: NowPlaying?
    public var items: [UpNextItem]

    public init(nowPlaying: NowPlaying? = nil, items: [UpNextItem] = []) {
        self.nowPlaying = nowPlaying
        self.items = items
    }

    public var isEmpty: Bool { nowPlaying == nil && items.isEmpty }
}

public enum UpNextSnapshotReason: String, Sendable, Codable {
    case replaced
    case cleared
    case restored
}

/// A former Up Next state ("Vorherige Warteschlangen"). It stores no playback position:
/// positions belong to the episodes and restoring never overwrites them.
public struct UpNextSnapshotValue: Hashable, Sendable, Codable {
    public var createdAt: Date
    public var reason: UpNextSnapshotReason
    public var state: UpNextState

    public init(createdAt: Date, reason: UpNextSnapshotReason, state: UpNextState) {
        self.createdAt = createdAt
        self.reason = reason
        self.state = state
    }
}

/// The Up Next history, newest first, limited to the last `limit` states.
public struct UpNextHistory: Sendable {
    public static let limit = 20

    public private(set) var snapshots: [UpNextSnapshotValue]

    public init(snapshots: [UpNextSnapshotValue] = []) {
        self.snapshots = Array(snapshots.sorted { $0.createdAt > $1.createdAt }.prefix(Self.limit))
    }

    public var isEmpty: Bool { snapshots.isEmpty }
    public var count: Int { snapshots.count }

    /// Records `state` before it gets replaced, cleared or restored over.
    /// An empty Up Next has nothing worth restoring and is not recorded.
    public mutating func record(_ state: UpNextState, reason: UpNextSnapshotReason, now: Date) {
        guard !state.isEmpty else { return }
        snapshots.insert(UpNextSnapshotValue(createdAt: now, reason: reason, state: state), at: 0)
        if snapshots.count > Self.limit { snapshots.removeLast(snapshots.count - Self.limit) }
    }
}
