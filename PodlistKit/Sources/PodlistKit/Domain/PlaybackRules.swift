import Foundation

/// Where playback starts, when the outro ends an episode and which speed applies
/// (concept §4.6 Player-Komfort, A8, N23, N25, N28, A28).
public enum PlaybackRules {
    /// Playback speeds the player offers, in steps of `speedStep`.
    public static let speedRange: ClosedRange<Double> = 0.5...3.0
    public static let speedStep = 0.1

    /// Where playback of an episode starts: the stored position, or the start if the episode
    /// is played (N23) or at the very end. A podcast's intro is skipped when playback would
    /// start inside it (A28), unless the intro is not shorter than the episode.
    public static func startPosition(
        stored: TimeInterval, isPlayed: Bool, duration: TimeInterval?, skipIntro: TimeInterval
    ) -> TimeInterval {
        var start = max(0, stored)
        if isPlayed { start = 0 }
        if let duration, start >= duration - 1 { start = 0 }
        if skipIntro > 0, start < skipIntro, duration.map({ skipIntro < $0 }) ?? true {
            start = skipIntro
        }
        return start
    }

    /// The time where the outro begins; nil without an outro setting or a known duration.
    public static func outroStart(duration: TimeInterval?, skipOutro: TimeInterval) -> TimeInterval? {
        guard skipOutro > 0, let duration, duration > skipOutro else { return nil }
        return duration - skipOutro
    }

    /// The longest step between two time observations that still counts as playing on
    /// (ticks are 0.5 s of media time; at 3x speed 1.5 s). Larger jumps are seeks.
    static let maxPlayingStep: TimeInterval = 5

    /// N28: playback ran across the outro mark. A seek into the outro does not count, so
    /// whoever seeks there hears it to the end.
    public static func reachesOutro(previous: TimeInterval, current: TimeInterval, outroStart: TimeInterval) -> Bool {
        previous < outroStart && current >= outroStart && current - previous <= maxPlayingStep
    }

    /// The speed in effect: the podcast's own (N25), else the global one.
    public static func speed(podcast: Double?, global: Double) -> Double {
        clampedSpeed(podcast ?? global)
    }

    /// Rounds to `speedStep` within `speedRange`; garbage becomes 1.
    public static func clampedSpeed(_ speed: Double) -> Double {
        guard speed.isFinite else { return 1 }
        let stepped = (speed / speedStep).rounded() * speedStep
        return min(max(stepped, speedRange.lowerBound), speedRange.upperBound)
    }
}
