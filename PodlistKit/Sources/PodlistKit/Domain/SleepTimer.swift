import Foundation

/// Sleep timer (concept §4.6, A27): counts only while playing, fades out over the last
/// `fadeDuration` seconds and fires once. The player feeds it; nothing here reads a clock.
public struct SleepTimer: Hashable, Sendable {
    public enum Mode: Hashable, Sendable {
        /// Playing time in seconds.
        case duration(TimeInterval)
        case endOfChapter
        /// N27: the episode ends as usual, the next one is only cued.
        case endOfEpisode
    }

    public static let fadeDuration: TimeInterval = 10

    public let mode: Mode
    /// `.duration`: playing seconds left.
    public private(set) var remaining: TimeInterval
    /// `.endOfChapter`: where the current chapter ends (set by the player, again after a seek);
    /// nil in the last chapter, then the timer ends with the episode.
    public var chapterEnd: TimeInterval?

    public init(_ mode: Mode) {
        self.mode = mode
        if case .duration(let seconds) = mode {
            remaining = max(0, seconds)
        } else {
            remaining = 0
        }
    }

    /// The player played on for `elapsed` wall-clock seconds. Steps that cannot be playing
    /// (backwards, zero, or a jump from a seek) are ignored.
    public mutating func advance(by elapsed: TimeInterval) {
        guard case .duration = mode, elapsed > 0, elapsed <= PlaybackRules.maxPlayingStep else { return }
        remaining = max(0, remaining - elapsed)
    }

    /// The episode's end pauses instead of playing on (end of episode, or end of a chapter
    /// that ends with the episode).
    public var endsWithEpisode: Bool {
        if case .duration = mode { return false }
        return true
    }

    /// Wall-clock seconds until the timer fires; nil if unknown. `episodeEnd` is where the
    /// episode ends (the outro mark or the duration).
    public func secondsLeft(at time: TimeInterval, rate: Double, episodeEnd: TimeInterval?) -> TimeInterval? {
        let rate = rate > 0 ? rate : 1
        switch mode {
        case .duration:
            return remaining
        case .endOfChapter:
            guard let end = chapterEnd ?? episodeEnd else { return nil }
            return max(0, end - time) / rate
        case .endOfEpisode:
            guard let episodeEnd else { return nil }
            return max(0, episodeEnd - time) / rate
        }
    }

    /// The player should pause now. The episode's own end is not "due": it pauses through
    /// `endsWithEpisode`, so Up Next can cue the next episode first.
    public func isDue(at time: TimeInterval, rate: Double, episodeEnd: TimeInterval?) -> Bool {
        switch mode {
        case .duration:
            return remaining <= 0
        case .endOfChapter:
            guard let chapterEnd else { return false }
            return time >= chapterEnd
        case .endOfEpisode:
            return false
        }
    }

    /// Volume factor for the fade-out: 1 until the last `fadeDuration` seconds, then linear to 0.
    public static func volume(secondsLeft: TimeInterval?) -> Float {
        guard let secondsLeft else { return 1 }
        return Float(min(1, max(0, secondsLeft / fadeDuration)))
    }
}
