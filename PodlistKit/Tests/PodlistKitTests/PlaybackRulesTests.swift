import Foundation
import Testing
@testable import PodlistKit

/// Where playback starts (A8, N23, intro skip A28), when the outro ends an episode (N28),
/// and the playback speed (N25).
struct PlaybackRulesTests {
    struct StartCase: CustomTestStringConvertible, Sendable {
        let name: String
        let stored: TimeInterval
        let isPlayed: Bool
        let duration: TimeInterval?
        let skipIntro: TimeInterval
        let expected: TimeInterval
        var testDescription: String { name }
    }

    @Test(arguments: [
        StartCase(name: "stored position", stored: 120, isPlayed: false, duration: 3_600, skipIntro: 0, expected: 120),
        StartCase(name: "played starts over (N23)", stored: 3_590, isPlayed: true, duration: 3_600, skipIntro: 0, expected: 0),
        StartCase(name: "at the very end starts over", stored: 3_599.5, isPlayed: false, duration: 3_600, skipIntro: 0, expected: 0),
        StartCase(name: "negative position", stored: -3, isPlayed: false, duration: nil, skipIntro: 0, expected: 0),
        StartCase(name: "intro skipped from the start", stored: 0, isPlayed: false, duration: 3_600, skipIntro: 45, expected: 45),
        StartCase(name: "intro skipped inside the intro", stored: 20, isPlayed: false, duration: 3_600, skipIntro: 45, expected: 45),
        StartCase(name: "intro not applied after it", stored: 300, isPlayed: false, duration: 3_600, skipIntro: 45, expected: 300),
        StartCase(name: "played starts after the intro", stored: 0, isPlayed: true, duration: 3_600, skipIntro: 45, expected: 45),
        StartCase(name: "intro longer than the episode is ignored", stored: 0, isPlayed: false, duration: 30, skipIntro: 45, expected: 0),
        StartCase(name: "intro with unknown duration", stored: 0, isPlayed: false, duration: nil, skipIntro: 45, expected: 45),
    ])
    func startPosition(_ c: StartCase) {
        let start = PlaybackRules.startPosition(
            stored: c.stored, isPlayed: c.isPlayed, duration: c.duration, skipIntro: c.skipIntro)
        #expect(start == c.expected)
    }

    @Test(arguments: [
        (3_600.0 as TimeInterval?, 60.0, 3_540.0 as TimeInterval?),
        (3_600, 0, nil),
        (nil, 60, nil),
        (50, 60, nil),
        (60, 60, nil),
    ] as [(TimeInterval?, TimeInterval, TimeInterval?)])
    func outroBoundary(duration: TimeInterval?, skipOutro: TimeInterval, expected: TimeInterval?) {
        #expect(PlaybackRules.outroStart(duration: duration, skipOutro: skipOutro) == expected)
    }

    /// N28: only playing across the mark ends the episode; seeking into the outro does not.
    @Test(arguments: [
        (3_539.5, 3_540.0, true),   // reaches the mark exactly
        (3_539.6, 3_540.1, true),   // crosses it while playing
        (3_540.0, 3_540.5, false),  // already inside (seeked in earlier): play the outro
        (3_500.0, 3_520.0, false),  // before the mark
        (1_000.0, 3_545.0, false),  // a seek across the mark
        (3_538.0, 3_541.0, true),   // a tick at 3x speed
    ] as [(TimeInterval, TimeInterval, Bool)])
    func reachingTheOutro(previous: TimeInterval, current: TimeInterval, expected: Bool) {
        #expect(PlaybackRules.reachesOutro(previous: previous, current: current, outroStart: 3_540) == expected)
    }

    @Test(arguments: [
        (nil as Double?, 1.0, 1.0),
        (1.5, 1.0, 1.5),
        (nil, 1.8, 1.8),
        (0.1, 1.0, 0.5),
        (9, 1.0, 3.0),
        (1.23, 1.0, 1.2),
        (1.26, 1.0, 1.3),
    ] as [(Double?, Double, Double)])
    func effectiveSpeed(podcast: Double?, global: Double, expected: Double) {
        #expect(abs(PlaybackRules.speed(podcast: podcast, global: global) - expected) < 0.0001)
    }

    @Test func speedSteps() {
        #expect(PlaybackRules.speedRange == 0.5...3.0)
        #expect(abs(PlaybackRules.clampedSpeed(1.149) - 1.1) < 0.0001)
        #expect(abs(PlaybackRules.clampedSpeed(.nan) - 1.0) < 0.0001)
    }
}
