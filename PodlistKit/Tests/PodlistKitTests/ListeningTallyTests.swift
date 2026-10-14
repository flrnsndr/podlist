import Foundation
import Testing
@testable import PodlistKit

/// Counting a listening session (plan-hoerstatistik §4.1).
struct ListeningTallyTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000_000)

    /// Ticks as (seconds after the start, position); the tally starts at position 100.
    @Test(arguments: [
        // Ticks every 0.5 s at 1×.
        TallyCase(ticks: [(0.5, 100.5), (1, 101), (1.5, 101.5)], listened: 1.5, content: 1.5),
        // 1.5×: more episode time than wall-clock time.
        TallyCase(ticks: [(0.5, 100.75), (1, 101.5)], listened: 1, content: 1.5),
        // A gap longer than 2 s (app frozen, stalled) does not count; ticks after it do.
        TallyCase(ticks: [(0.5, 100.5), (30, 101), (30.5, 101.5)], listened: 1, content: 1),
        // The position did not move (paused, buffering): no listening.
        TallyCase(ticks: [(0.5, 100), (1, 100)], listened: 0, content: 0),
        // An unreported jump is not listening.
        TallyCase(ticks: [(0.5, 100.5), (1, 400)], listened: 0.5, content: 0.5),
        // Going backwards without a seek (stale tick) is not listening either.
        TallyCase(ticks: [(0.5, 99), (1, 99.5)], listened: 0.5, content: 0.5),
    ])
    func ticksCountOnlyPlausiblePlayback(_ testCase: TallyCase) {
        var tally = ListeningTally(episode: EpisodeID(), at: start, position: 100)
        for (seconds, position) in testCase.ticks {
            tally.tick(at: start.addingTimeInterval(seconds), position: position)
        }
        #expect(tally.listenedSeconds == testCase.listened)
        #expect(tally.contentSeconds == testCase.content)
        #expect(tally.endedAt == start.addingTimeInterval(testCase.ticks.last!.0))
        #expect(tally.endPosition == testCase.ticks.last!.1)
        #expect(tally.startPosition == 100 && tally.startedAt == start)
    }

    @Test func seeksAreSkipsNotListening() {
        var tally = ListeningTally(episode: EpisodeID(), at: start, position: 100)
        tally.tick(at: start.addingTimeInterval(0.5), position: 100.5)
        tally.seek(from: 100.5, to: 130.5)
        tally.tick(at: start.addingTimeInterval(1), position: 131)
        tally.seek(from: 131, to: 116)
        tally.tick(at: start.addingTimeInterval(1.5), position: 116.5)
        #expect(tally.skippedForwardSeconds == 30)
        #expect(tally.skippedBackwardSeconds == 15)
        #expect(tally.listenedSeconds == 1.5)
        #expect(tally.contentSeconds == 1.5)
        #expect(tally.endPosition == 116.5)
    }

    @Test func shortSessionsAreNotKept() {
        var tally = ListeningTally(episode: EpisodeID(), at: start, position: 0)
        for tick in 1...9 { tally.tick(at: start.addingTimeInterval(Double(tick) * 0.5), position: Double(tick) * 0.5) }
        #expect(tally.listenedSeconds == 4.5)
        #expect(!tally.isWorthKeeping)
        tally.tick(at: start.addingTimeInterval(5), position: 5)
        #expect(tally.isWorthKeeping)
    }
}

struct TallyCase: Sendable, CustomTestStringConvertible {
    let ticks: [(TimeInterval, TimeInterval)]
    let listened: TimeInterval
    let content: TimeInterval
    var testDescription: String { "\(ticks.map { "\($0.0)s→\($0.1)" }.joined(separator: ", "))" }
}
