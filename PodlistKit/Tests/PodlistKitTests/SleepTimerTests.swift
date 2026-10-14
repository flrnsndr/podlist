import Foundation
import Testing
@testable import PodlistKit

/// Sleep timer (concept §4.6, A27, N27): counts only while playing, fades out over the last
/// seconds, fires once.
struct SleepTimerTests {
    @Test func durationCountsDownOnlyByPlayingTime() {
        var timer = SleepTimer(.duration(600))
        timer.advance(by: 0.5)
        timer.advance(by: 0.5)
        #expect(timer.remaining == 599)
        #expect(timer.secondsLeft(at: 100, rate: 2, episodeEnd: 3_600) == 599)
        #expect(!timer.isDue(at: 100, rate: 2, episodeEnd: 3_600))
        for _ in 0..<1_198 { timer.advance(by: 0.5) }
        #expect(timer.isDue(at: 100, rate: 2, episodeEnd: 3_600))
        timer.advance(by: 5)
        #expect(timer.remaining == 0)
    }

    /// Big jumps (a seek reported by the time observer) or going backwards do not count.
    @Test(arguments: [-5.0, 0, 30, .nan, .infinity])
    func implausibleStepsAreIgnored(step: TimeInterval) {
        var timer = SleepTimer(.duration(600))
        timer.advance(by: step)
        #expect(timer.remaining == 600)
    }

    @Test func endOfChapterUsesTheChapterEndAndTheRate() {
        var timer = SleepTimer(.endOfChapter)
        timer.chapterEnd = 1_200
        #expect(timer.secondsLeft(at: 1_100, rate: 2, episodeEnd: 3_600) == 50)
        #expect(!timer.isDue(at: 1_199.9, rate: 1, episodeEnd: 3_600))
        #expect(timer.isDue(at: 1_200, rate: 1, episodeEnd: 3_600))
        // The last chapter (no end known): it fires with the episode, not before.
        timer.chapterEnd = nil
        #expect(timer.secondsLeft(at: 3_000, rate: 1, episodeEnd: 3_600) == 600)
        #expect(!timer.isDue(at: 3_600, rate: 1, episodeEnd: 3_600))
    }

    /// N27: "Ende der Folge" never pauses by itself; the episode end does that (next one cued).
    @Test func endOfEpisodeFiresWithTheEpisodeEnd() {
        let timer = SleepTimer(.endOfEpisode)
        #expect(timer.endsWithEpisode)
        #expect(timer.secondsLeft(at: 3_590, rate: 1, episodeEnd: 3_600) == 10)
        #expect(timer.secondsLeft(at: 3_590, rate: 1, episodeEnd: nil) == nil)
        #expect(!timer.isDue(at: 3_600, rate: 1, episodeEnd: 3_600))
        #expect(!SleepTimer(.duration(60)).endsWithEpisode)
        // An end-of-chapter timer in the last chapter also ends with the episode.
        #expect(SleepTimer(.endOfChapter).endsWithEpisode)
    }

    @Test(arguments: [
        (nil as TimeInterval?, 1.0 as Float),
        (60, 1),
        (10, 1),
        (5, 0.5),
        (1, 0.1),
        (0, 0),
        (-2, 0),
    ] as [(TimeInterval?, Float)])
    func fadeOut(secondsLeft: TimeInterval?, volume: Float) {
        #expect(abs(SleepTimer.volume(secondsLeft: secondsLeft) - volume) < 0.0001)
    }
}
