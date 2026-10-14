import Foundation

/// Why a listening session ended (plan-hoerstatistik §3). A session that is still open is
/// stored as `interrupted`, so a session cut short by the app being killed needs no repair.
public enum ListeningEndReason: String, Codable, Sendable, CaseIterable {
    case paused
    /// The episode played to its end or reached its outro (N28).
    case finished
    case sleepTimer
    /// Another episode came into the player.
    case switched
    case interrupted
}

/// Counts one listening session: one episode playing from ▶ to pause, end or switch
/// (plan-hoerstatistik §4.1). Pure value logic; the caller passes the time.
///
/// Listening time only grows between two ticks that are close together and in which the
/// episode's position moved forward plausibly; seeks are reported separately and never
/// count as listening.
public struct ListeningTally: Equatable, Sendable {
    /// A longer gap between ticks means the app was frozen or the player stalled.
    public static let maxTickGap: TimeInterval = 2
    /// Position progress beyond this many times the wall-clock time is a jump, not playback.
    static let maxRate: Double = 4
    /// Shorter sessions are accidental starts and are not kept.
    public static let minimumListened: TimeInterval = 5

    public let episode: EpisodeID
    public let startedAt: Date
    public let startPosition: TimeInterval
    public private(set) var endedAt: Date
    public private(set) var endPosition: TimeInterval
    /// Wall-clock seconds the episode was playing.
    public private(set) var listenedSeconds: TimeInterval = 0
    /// Episode seconds that went by while playing (≈ listened × speed).
    public private(set) var contentSeconds: TimeInterval = 0
    public private(set) var skippedForwardSeconds: TimeInterval = 0
    public private(set) var skippedBackwardSeconds: TimeInterval = 0

    public init(episode: EpisodeID, at now: Date, position: TimeInterval) {
        self.episode = episode
        startedAt = now
        startPosition = position
        endedAt = now
        endPosition = position
    }

    /// The player reported `position` at `now` while playing.
    public mutating func tick(at now: Date, position: TimeInterval) {
        let wall = now.timeIntervalSince(endedAt)
        let progress = position - endPosition
        if wall > 0, wall <= Self.maxTickGap, progress > 0, progress <= wall * Self.maxRate + 0.5 {
            listenedSeconds += wall
            contentSeconds += progress
        }
        if now > endedAt { endedAt = now }
        endPosition = position
    }

    /// The listener moved from `from` to `to` (skip buttons, chapters, scrubber).
    public mutating func seek(from: TimeInterval, to: TimeInterval) {
        if to > from {
            skippedForwardSeconds += to - from
        } else {
            skippedBackwardSeconds += from - to
        }
        endPosition = to
    }

    /// Long enough to be stored.
    public var isWorthKeeping: Bool { listenedSeconds >= Self.minimumListened }
}
