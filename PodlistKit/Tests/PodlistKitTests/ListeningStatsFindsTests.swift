import Foundation
import Testing
@testable import PodlistKit

// F. Finds (I25, I37–I44) and G. Library and bad conscience (I26–I28).
struct ListeningStatsFindsTests {
    private let a = StatsShow("A")
    private let b = StatsShow("B")
    private let c = StatsShow("C")

    // MARK: I25

    @Test func archaeologistFindsTheOldestEpisodeAtLeastAYearOld() {
        let records = [
            statsRec(statsAt(2026, 9, 5, 8), minutes: 20, a, published: statsAt(2014, 3, 10), title: "Old"),
            statsRec(statsAt(2026, 9, 6, 8), minutes: 20, a, published: statsAt(2019, 1, 1), title: "Younger"),
        ]
        let found = statsReport(statsSep, records).archaeologist
        #expect(found?.title == "Old" && found?.date == statsAt(2014, 3, 10))
    }

    @Test(arguments: [(published: (2025, 9, 6), expected: false), (published: (2025, 9, 5), expected: true)])
    func archaeologistNeedsAYear(published: (Int, Int, Int), expected: Bool) {
        let date = statsAt(published.0, published.1, published.2, 8)
        let found = statsReport(statsSep, [statsRec(statsAt(2026, 9, 5, 8), minutes: 20, a, published: date)]).archaeologist
        #expect((found != nil) == expected)
    }

    // MARK: I37

    @Test(arguments: [(delay: 3_600.0, expected: true), (delay: 3_601.0, expected: false)])
    func quickestNeedsAnHour(delay: Double, expected: Bool) {
        let start = statsAt(2026, 9, 5, 8)
        let record = statsRec(start, minutes: 20, a, published: start.addingTimeInterval(-delay), title: "Fast")
        let quickest = statsReport(statsSep, [record]).quickest
        #expect((quickest != nil) == expected)
        if expected { #expect(quickest?.delay == delay && quickest?.0.date == start && quickest?.0.title == "Fast") }
    }

    @Test func quickestIgnoresEpisodesHeardBeforeAndUnpublishedOnes() {
        let again = EpisodeID()
        let start = statsAt(2026, 9, 5, 8)
        let records = [
            statsRec(statsAt(2026, 8, 5, 8), minutes: 20, a, episode: again, published: statsAt(2026, 8, 5, 7, 59)),
            statsRec(start, minutes: 20, a, episode: again, published: statsAt(2026, 8, 5, 7, 59)),
            statsRec(start, minutes: 20, b),
        ]
        #expect(statsReport(statsSep, records).quickest == nil)
    }

    // MARK: I38

    @Test(arguments: [(finishes: 1, expected: false), (finishes: 2, expected: true)])
    func repeatedNeedsTwoFinishes(finishes: Int, expected: Bool) {
        let episode = EpisodeID()
        let records = (0 ..< finishes).map { statsRec(statsAt(2026, 9, 5 + $0, 8), minutes: 20, a, episode: episode, reason: .finished, title: "Again") }
            + [statsRec(statsAt(2026, 9, 20, 8), minutes: 20, b, reason: .finished)]
        let repeated = statsReport(statsSep, records).repeated
        #expect((repeated != nil) == expected)
        if expected { #expect(repeated?.times == 2 && repeated?.0.title == "Again") }
    }

    // MARK: I39 / I40

    @Test(arguments: [(duration: 7_199.0, expected: false), (duration: 7_200.0, expected: true)])
    func longestEpisodeNeedsTwoHours(duration: Double, expected: Bool) {
        let records = [
            statsRec(statsAt(2026, 9, 5, 8), minutes: 20, a, reason: .finished, duration: duration, title: "Big"),
            // Long but not finished: does not count.
            statsRec(statsAt(2026, 9, 6, 8), minutes: 20, b, duration: 20_000),
        ]
        let longest = statsReport(statsSep, records).longestEpisode
        #expect((longest != nil) == expected)
        if expected { #expect(longest?.duration == duration && longest?.0.title == "Big") }
    }

    @Test(arguments: [(duration: 601.0, expected: false), (duration: 600.0, expected: true)])
    func shortestEpisodeNeedsTenMinutesOrLess(duration: Double, expected: Bool) {
        let records = [
            statsRec(statsAt(2026, 9, 5, 8), minutes: 5, a, reason: .finished, duration: duration),
            statsRec(statsAt(2026, 9, 6, 8), minutes: 5, b, reason: .finished, duration: 2_000),
            statsRec(statsAt(2026, 9, 7, 8), minutes: 5, c, reason: .finished),
        ]
        let shortest = statsReport(statsSep, records).shortestEpisode
        #expect((shortest != nil) == expected)
        if expected { #expect(shortest?.duration == duration) }
    }

    // MARK: I41

    @Test(arguments: [(firstDay: 7, expected: false), (firstDay: 6, expected: true)])
    func longHaulNeedsThirtyDays(firstDay: Int, expected: Bool) {
        let episode = EpisodeID()
        let records = [
            statsRec(statsAt(2026, 8, firstDay, 23), minutes: 20, a, episode: episode, title: "Slow"),
            statsRec(statsAt(2026, 9, 5, 8), minutes: 20, a, episode: episode, reason: .finished, title: "Slow"),
        ]
        let haul = statsReport(statsSep, records).longHaul
        #expect((haul != nil) == expected)
        if expected { #expect(haul?.days == 30 && haul?.0.date == statsAt(2026, 9, 5, 8, 20)) }
    }

    @Test func longHaulCountsWhereTheEpisodeWasFinished() {
        let episode = EpisodeID()
        let records = [
            statsRec(statsAt(2026, 6, 1, 8), minutes: 20, a, episode: episode),
            statsRec(statsAt(2026, 9, 5, 8), minutes: 20, a, episode: episode, reason: .finished),
        ]
        #expect(statsReport(statsSep, records).longHaul?.days == 96)
        #expect(statsReport(.month(year: 2026, month: 6), records).longHaul == nil)
    }

    @Test func longHaulStartsOverAfterAFinish() {
        let episode = EpisodeID()
        let records = [
            statsRec(statsAt(2026, 1, 10, 8), minutes: 20, a, episode: episode, reason: .finished),
            statsRec(statsAt(2026, 9, 1, 8), minutes: 20, a, episode: episode),
            statsRec(statsAt(2026, 9, 5, 8), minutes: 20, a, episode: episode, reason: .finished),
        ]
        // Heard again from 1 September: 4 days, not since January.
        #expect(statsReport(statsSep, records).longHaul == nil)
        let slow = records.dropLast() + [statsRec(statsAt(2026, 10, 15, 8), minutes: 20, a, episode: episode, reason: .finished)]
        #expect(statsReport(statsOct, Array(slow)).longHaul?.days == 44)
    }

    // MARK: I42

    @Test func nightShiftIsTheLatestMomentBeforeFourInTheMorning() {
        let records = [
            statsRec(statsAt(2026, 9, 8, 2, 50), minutes: 22, a, title: "Late"),
            statsRec(statsAt(2026, 9, 9, 1, 0), minutes: 20, b),
            // After 4 o'clock is morning.
            statsRec(statsAt(2026, 9, 10, 4, 30), minutes: 20, c),
        ]
        let night = statsReport(statsSep, records).nightShift
        #expect(night?.title == "Late" && night?.date == statsAt(2026, 9, 8, 3, 12))
        #expect(statsReport(statsSep, [records[2]]).nightShift == nil)
    }

    @Test func nightShiftSeesASessionOverMidnight() {
        let night = statsReport(statsSep, [statsRec(statsAt(2026, 9, 8, 23, 50), minutes: 30, a)]).nightShift
        #expect(night?.date == statsAt(2026, 9, 9, 0, 20))
    }

    // MARK: I43 / I44

    @Test func firstAndLastOfTheYearNeedTwoMonths() {
        let records = [
            statsRec(statsAt(2026, 1, 3, 8), minutes: 20, a, title: "First"),
            statsRec(statsAt(2026, 5, 4, 8), minutes: 20, b),
            statsRec(statsAt(2026, 12, 30, 20), minutes: 20, c, title: "Last"),
        ]
        let result = statsReport(statsYear, records, now: statsAt(2027, 1, 5)).firstAndLast
        #expect(result?.first.title == "First" && result?.first.date == statsAt(2026, 1, 3, 8))
        #expect(result?.last.title == "Last" && result?.last.date == statsAt(2026, 12, 30, 20, 20))
        #expect(statsReport(statsYear, [records[0], statsRec(statsAt(2026, 1, 20, 8), minutes: 20, a)]).firstAndLast == nil)
        #expect(statsReport(statsSep, records).firstAndLast == nil)
    }

    @Test func holidaysListTheLatestMomentPerDayInOrder() {
        let records = [
            statsRec(statsAt(2026, 1, 1, 10), minutes: 20, a, title: "Day"),
            statsRec(statsAt(2026, 12, 24, 9), minutes: 20, a),
            statsRec(statsAt(2026, 12, 24, 23, 10), minutes: 20, b, title: "Eve"),
            statsRec(statsAt(2026, 12, 31, 23, 21), minutes: 20, c, title: "Silvester"),
            statsRec(statsAt(2026, 6, 1, 10), minutes: 20, a),
        ]
        let holidays = statsReport(statsYear, records, now: statsAt(2027, 1, 5)).holidays
        #expect(holidays?.map(\.holiday) == [.christmasEve, .newYearsEve, .newYearsDay])
        #expect(holidays?[0].moment.title == "Eve" && holidays?[0].moment.date == statsAt(2026, 12, 24, 23, 30))
        #expect(holidays?[1].moment.date == statsAt(2026, 12, 31, 23, 41))
        #expect(statsReport(statsYear, [records[4]], now: statsAt(2027, 1, 5)).holidays == nil)
        #expect(statsReport(.month(year: 2026, month: 12), records).holidays == nil)
    }

    // MARK: I26

    @Test func neglectedPodcastsHaveNewEpisodesAndNoListening() {
        func dates(_ count: Int) -> [Date] { (0 ..< count).map { statsAt(2026, 9, 1 + $0, 6) } }
        let heard = StatsShow("Heard"), others = (1 ... 4).map { StatsShow("N\($0)") }
        let library = StatsLibrary(podcasts: [
            others[0].podcast(subscribedAt: statsAt(2026, 8, 1), published: dates(9)),
            others[1].podcast(subscribedAt: statsAt(2026, 8, 1), published: dates(3)),
            others[2].podcast(subscribedAt: statsAt(2026, 8, 1), published: dates(2)),
            others[3].podcast(subscribedAt: statsAt(2026, 8, 1), published: dates(1)),
            heard.podcast(subscribedAt: statsAt(2026, 8, 1), published: dates(5)),
            StatsShow("New").podcast(subscribedAt: statsAt(2026, 9, 2), published: dates(5)),
            StatsShow("Cancelled").podcast(subscribedAt: statsAt(2026, 8, 1), isSubscribed: false, published: dates(5)),
            StatsShow("Quiet").podcast(subscribedAt: statsAt(2026, 8, 1), published: []),
        ])
        let sessions = [statsRec(statsAt(2026, 9, 5, 8), minutes: 20, heard)]
        let list = statsReport(statsSep, sessions, library: library).neglected
        #expect(list?.map(\.podcast.title) == ["N1", "N2", "N3"])
        #expect(list?.map(\.newEpisodes) == [9, 3, 2])
        #expect(statsReport(statsSep, sessions, library: StatsLibrary(podcasts: [library.podcasts[4]])).neglected == nil)
    }

    // MARK: I27

    @Test(arguments: [(backlog: 3_599.0, expected: false), (backlog: 3_600.0, expected: true)])
    func backlogNeedsAnHour(backlog: Double, expected: Bool) {
        // 10 h over 20 days: 30 min a day.
        let records = [statsRec(statsAt(2026, 10, 1, 8), minutes: 600, a)]
        let result = statsReport(statsOct, records, library: StatsLibrary(backlogSeconds: backlog)).backlog
        #expect((result != nil) == expected)
        if expected { #expect(result?.days == 2 && result?.nonstopDays == 1) }
    }

    @Test func backlogDaysFollowThePaceAndSpeed() {
        let library = StatsLibrary(backlogSeconds: 36 * 3_600)
        // 10 h in 20 days → 1800 s a day at 1×: 72 days; the backlog is 1.5 days long.
        let slow = statsReport(statsOct, [statsRec(statsAt(2026, 10, 1, 8), minutes: 600, a)], library: library).backlog
        #expect(slow?.days == 72 && slow?.nonstopDays == 2)
        // At 2× the same backlog goes twice as fast.
        let fast = statsReport(statsOct, [statsRec(statsAt(2026, 10, 1, 8), minutes: 600, a, speed: 2)], library: library).backlog
        #expect(fast?.days == 36 && fast?.nonstopDays == 1)
    }

    @Test func backlogPaceCountsFromTheStartOfRecording() {
        // Recording started on 11 October: 10 h in 10 days, 1 h a day.
        let records = [statsRec(statsAt(2026, 10, 11, 8), minutes: 600, a)]
        let result = statsReport(statsOct, records, library: StatsLibrary(backlogSeconds: 20 * 3_600)).backlog
        #expect(result?.days == 20)
    }

    @Test func backlogIsForTheCurrentMonthOnly() {
        let library = StatsLibrary(backlogSeconds: 36 * 3_600)
        let records = [statsRec(statsAt(2026, 9, 2, 8), minutes: 600, a), statsRec(statsAt(2026, 10, 2, 8), minutes: 600, a)]
        #expect(statsReport(statsSep, records, library: library).backlog == nil)
        #expect(statsReport(statsYear, records, library: library).backlog == nil)
        #expect(statsReport(statsOct, records, library: library, now: statsAt(2026, 11, 3)).backlog == nil)
    }

    // MARK: I28

    @Test func unheardSubscriptionsOfTheYear() {
        let heard = StatsShow("Heard")
        // 30 days before "now" (20 Oct, noon) is 20 Sep, noon.
        let library = StatsLibrary(podcasts: [
            heard.podcast(subscribedAt: statsAt(2026, 1, 1)),
            StatsShow("Old").podcast(subscribedAt: statsAt(2025, 1, 1)),
            StatsShow("Edge").podcast(subscribedAt: statsAt(2026, 9, 20, 12)),
            StatsShow("TooNew").podcast(subscribedAt: statsAt(2026, 9, 20, 13)),
            StatsShow("Gone").podcast(subscribedAt: statsAt(2025, 1, 1), isSubscribed: false),
        ])
        let sessions = [statsRec(statsAt(2026, 9, 5, 8), minutes: 20, heard)]
        #expect(statsReport(statsYear, sessions, library: library).unheardSubscriptions == 2)
        #expect(statsReport(statsSep, sessions, library: library).unheardSubscriptions == nil)
        let allHeard = StatsLibrary(podcasts: [library.podcasts[0]])
        #expect(statsReport(statsYear, sessions, library: allHeard).unheardSubscriptions == nil)
    }
}
