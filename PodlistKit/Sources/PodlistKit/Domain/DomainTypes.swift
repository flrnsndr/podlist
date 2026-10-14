import Foundation

// Shared value types for the pure domain logic. Domain code never touches `@Model`
// objects; services translate models into these types and back.

public struct EpisodeID: Hashable, Sendable, Codable {
    public var uuid: UUID
    public init(_ uuid: UUID = UUID()) { self.uuid = uuid }
}

public struct PlaylistID: Hashable, Sendable, Codable {
    public var uuid: UUID
    public init(_ uuid: UUID = UUID()) { self.uuid = uuid }
}

public struct PodcastID: Hashable, Sendable, Codable {
    public var uuid: UUID
    public init(_ uuid: UUID = UUID()) { self.uuid = uuid }
}

/// What happens to a played episode in a playlist (concept §4.3).
public enum PlayedPolicy: String, Sendable, Codable, CaseIterable {
    /// Default: a played episode disappears from the playlist.
    case remove
    /// The episode stays; playing the playlist also plays already played episodes.
    case keep
}

/// Rule of a podcast ↔ playlist assignment (concept §4.1).
public enum AutoAddRule: String, Sendable, Codable, CaseIterable {
    case off
    case top
    case bottom
}

/// Display sort of a playlist (concept §4.2). Only `manual` uses the stored `position`.
public enum PlaylistSort: String, Sendable, Codable, CaseIterable {
    case published
    case duration
    case added
    case title
    case podcast
    case manual
}

/// The episode fields that sorting, automation and played rules need.
public struct EpisodeInfo: Hashable, Sendable {
    public var id: EpisodeID
    public var podcastID: PodcastID
    public var podcastTitle: String
    public var title: String
    public var publishedAt: Date
    public var duration: TimeInterval?
    public var playbackPosition: TimeInterval
    public var playedAt: Date?

    public var isPlayed: Bool { playedAt != nil }

    public init(
        id: EpisodeID = EpisodeID(),
        podcastID: PodcastID,
        podcastTitle: String,
        title: String,
        publishedAt: Date,
        duration: TimeInterval? = nil,
        playbackPosition: TimeInterval = 0,
        playedAt: Date? = nil
    ) {
        self.id = id
        self.podcastID = podcastID
        self.podcastTitle = podcastTitle
        self.title = title
        self.publishedAt = publishedAt
        self.duration = duration
        self.playbackPosition = playbackPosition
        self.playedAt = playedAt
    }
}

/// One episode at a position in a playlist.
public struct PlaylistEntryInfo: Hashable, Sendable {
    public var episode: EpisodeInfo
    public var position: Double
    public var addedAt: Date

    public init(episode: EpisodeInfo, position: Double, addedAt: Date) {
        self.episode = episode
        self.position = position
        self.addedAt = addedAt
    }
}

/// Ordering via `position: Double` (concept §4.2): top = min − 1, bottom = max + 1,
/// between = midpoint. Nothing ever needs renumbering.
public enum Position {
    public static func top(above positions: some Sequence<Double>) -> Double {
        (positions.min() ?? 1) - 1
    }

    public static func bottom(below positions: some Sequence<Double>) -> Double {
        (positions.max() ?? -1) + 1
    }

    public static func between(_ a: Double, _ b: Double) -> Double {
        (a + b) / 2
    }

    /// New positions after moving the items at `offsets` to `destination` (SwiftUI
    /// `onMove` semantics, `positions` in display order). Only the moved items change:
    /// they are spread evenly between their new neighbours. Keyed by original index.
    public static func afterMove(_ positions: [Double], fromOffsets offsets: IndexSet, toOffset destination: Int) -> [Int: Double] {
        let moved = positions.indices.filter { offsets.contains($0) }
        guard !moved.isEmpty else { return [:] }
        let rest = positions.indices.filter { !offsets.contains($0) }
        let insertAt = min(max(0, destination - moved.count { $0 < destination }), rest.count)
        let lower = insertAt > 0 ? positions[rest[insertAt - 1]] : nil
        let upper = insertAt < rest.count ? positions[rest[insertAt]] : nil

        let count = Double(moved.count)
        var result: [Int: Double] = [:]
        for (offset, index) in moved.enumerated() {
            let step = Double(offset)
            switch (lower, upper) {
            case let (lower?, upper?): result[index] = lower + (upper - lower) * (step + 1) / (count + 1)
            case let (lower?, nil): result[index] = lower + step + 1
            case let (nil, upper?): result[index] = upper - count + step
            case (nil, nil): result[index] = step
            }
        }
        return result
    }
}
