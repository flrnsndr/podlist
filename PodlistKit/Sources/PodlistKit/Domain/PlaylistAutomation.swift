import Foundation

/// A podcast ↔ playlist assignment with its auto-add rule.
public struct PlaylistAssignmentInfo: Hashable, Sendable {
    public var playlistID: PlaylistID
    public var rule: AutoAddRule
    public init(playlistID: PlaylistID, rule: AutoAddRule) {
        self.playlistID = playlistID
        self.rule = rule
    }
}

/// An entry that must be inserted into a playlist.
public struct PlaylistInsertion: Hashable, Sendable {
    public var playlistID: PlaylistID
    public var entry: PlaylistEntryInfo
}

/// Auto-add logic (concept §4.1). Top/bottom only affects `position` (manual sort).
public enum PlaylistAutomation {
    /// New episodes of one podcast arrived. `existingEntries` holds the current entries per playlist.
    public static func insertions(
        forNewEpisodes newEpisodes: [EpisodeInfo],
        assignments: [PlaylistAssignmentInfo],
        existingEntries: [PlaylistID: [PlaylistEntryInfo]],
        now: Date
    ) -> [PlaylistInsertion] {
        assignments.flatMap { assignment in
            place(
                newEpisodes, rule: assignment.rule, playlistID: assignment.playlistID,
                existing: existingEntries[assignment.playlistID] ?? [], now: now)
        }
    }

    private static func place(
        _ episodes: [EpisodeInfo], rule: AutoAddRule, playlistID: PlaylistID,
        existing: [PlaylistEntryInfo], now: Date
    ) -> [PlaylistInsertion] {
        guard rule != .off else { return [] }
        let present = Set(existing.map(\.episode.id))
        let fresh = episodes.filter { !present.contains($0.id) }
            .sorted { $0.publishedAt != $1.publishedAt ? $0.publishedAt < $1.publishedAt : $0.id.uuid.uuidString < $1.id.uuid.uuidString }
        let positions = existing.map(\.position)
        // Oldest first. Top: oldest sits just above the minimum, newest ends up on top.
        let base: [Double]
        switch rule {
        case .top:
            let start = Position.top(above: positions)
            base = fresh.indices.map { start - Double($0) }
        case .bottom:
            let start = Position.bottom(below: positions)
            base = fresh.indices.map { start + Double($0) }
        case .off:
            base = []
        }
        return zip(fresh, base).map {
            PlaylistInsertion(
                playlistID: playlistID,
                entry: PlaylistEntryInfo(episode: $0, position: $1, addedAt: now))
        }
    }
}
