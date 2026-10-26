import Foundation

/// A playlist containing an episode, with its played policy.
public struct PlaylistPolicy: Hashable, Sendable {
    public var playlistID: PlaylistID
    public var policy: PlayedPolicy
    public init(playlistID: PlaylistID, policy: PlayedPolicy) {
        self.playlistID = playlistID
        self.policy = policy
    }
}

/// "Played" rules (concept §4.3).
public enum PlayedRules {
    /// ASSUMPTION: default near-end threshold is 30 seconds (the setting is user-adjustable).
    public static let defaultThreshold: TimeInterval = 30

    /// True if the remaining time is at most `threshold`. Unknown or zero duration: false.
    public static func isNearEnd(
        position: TimeInterval, duration: TimeInterval?, threshold: TimeInterval = defaultThreshold
    ) -> Bool {
        guard let duration, duration > 0 else { return false }
        return duration - position <= threshold
    }

    /// Whether an episode counts as played after a progress update.
    public static func shouldMarkPlayed(
        finished: Bool, position: TimeInterval, duration: TimeInterval?,
        threshold: TimeInterval = defaultThreshold
    ) -> Bool {
        finished || isNearEnd(position: position, duration: duration, threshold: threshold)
    }

    /// Playlists a played episode must be removed from (`remove` only; `keep` stays).
    /// The episode that is playing is never removed (A37: it keeps its file and its place).
    /// Apply the policy once it stops playing (ended, skipped, replaced, interrupted).
    /// Marking unplayed never re-adds it anywhere.
    public static func playlistsToRemoveFrom(_ playlists: [PlaylistPolicy], isNowPlaying: Bool) -> [PlaylistID] {
        guard !isNowPlaying else { return [] }
        return playlists.filter { $0.policy == .remove }.map(\.playlistID)
    }

}
