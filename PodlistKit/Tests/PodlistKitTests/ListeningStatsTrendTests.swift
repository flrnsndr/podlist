import Foundation
import Testing
@testable import PodlistKit

// H. Developments over time (I29–I36) and the period list.
struct ListeningStatsTrendTests {
    private let a = StatsShow("A")
    private let b = StatsShow("B")
    private let c = StatsShow("C")

    /// A month's listening as (podcast, minutes) entries on day 5, one session each.
    private func month(
        _ year: Int, _ month: Int, _ entries: [(StatsShow, Double)], hour: Int = 6, speed: Double = 1, playlists: [PlaylistID?] = []
    ) -> [ListeningRecord] {
        var records: [ListeningRecord] = []
        for (index, entry) in entries.enumerated() {
            records.append(statsRec(
                statsAt(year, month, 5, hour), minutes: entry.1, entry.0, playlist: index < playlists.count ? playlists[index] : nil,
                speed: speed))
        }
        return records
    }

    // MARK: Periods

    @Test func periodsListThoseWithSessionsPlusTheCurrentOne() {
        let records = [
            statsRec(statsAt(2026, 7, 5, 8), minutes: 20, a), statsRec(statsAt(2026, 7, 9, 8), minutes: 20, a),
            statsRec(statsAt(2026, 9, 5, 8), minutes: 20, a),
        ]
        let months = ListeningStats.periods(.month, sessions: records, calendar: statsCalendar, now: statsNow)
        #expect(months == [.month(year: 2026, month: 7), .month(year: 2026, month: 9), .month(year: 2026, month: 10)])
        #expect(ListeningStats.periods(.year, sessions: [], calendar: statsCalendar, now: statsNow) == [.year(2026)])
    }

    // MARK: I29

    @Test(arguments: [(days: 2, expected: false), (days: 3, expected: true)])
    func monthlyTrendNeedsThreeListeningDays(days: Int, expected: Bool) {
        let records = (1 ... days).map { statsRec(statsAt(2026, 10, $0, 8), minutes: 60, a) }
        let trend = statsReport(statsOct, records).trend
        #expect((trend != nil) == expected)
        // Bars stop at today (20 October).
        if expected { #expect(trend?.bars.count == 20 && trend?.bars.first?.start == statsAt(2026, 10, 1, 0) && near(trend?.average, 540)) }
    }

    @Test func pastMonthHasABarForEveryDay() {
        let records = (1 ... 3).map { statsRec(statsAt(2026, 9, $0, 8), minutes: 60, a) }
        #expect(statsReport(statsSep, records).trend?.bars.count == 30)
    }

    @Test(arguments: [(months: 1, expected: false), (months: 2, expected: true)])
    func yearlyTrendNeedsTwoMonths(months: Int, expected: Bool) {
        let records = (1 ... months).map { statsRec(statsAt(2026, $0, 5, 8), minutes: 60, a) }
        let trend = statsReport(statsYear, records).trend
        #expect((trend != nil) == expected)
        // January to October, up to the current month.
        if expected { #expect(trend?.bars.count == 10 && trend?.bars[1].start == statsAt(2026, 2, 1, 0) && near(trend?.average, 720)) }
    }

    @Test func barsStartWithTheRecording() {
        let records = (9 ... 11).map { statsRec(statsAt(2026, 10, $0, 8), minutes: 60, a) }
        let month = statsReport(statsOct, records).trend
        #expect(month?.bars.first?.start == statsAt(2026, 10, 9, 0) && month?.bars.count == 12)
        let yearRecords = [statsRec(statsAt(2026, 9, 20, 8), minutes: 60, a), statsRec(statsAt(2026, 10, 5, 8), minutes: 60, a)]
        let year = statsReport(statsYear, yearRecords).trend
        #expect(year?.bars.map(\.start) == [statsAt(2026, 9, 1, 0), statsAt(2026, 10, 1, 0)] && near(year?.average, 3_600))
    }

    // MARK: I30 / I31 month view

    /// July, August, September: A 60 % / B 40 %.
    private var earlier: [ListeningRecord] {
        (7 ... 9).flatMap { month(2026, $0, [(a, 60), (b, 40)]) }
    }

    @Test func riserAndCooledInAMonth() {
        let records = earlier + month(2026, 10, [(a, 20), (b, 40), (c, 40)])
        let report = statsReport(statsOct, records)
        let riser = report.riser, cooled = report.cooled
        #expect(riser?.podcast.title == "C" && near(riser?.fromShare, 0) && near(riser?.toShare, 0.4))
        #expect(riser?.fromRank == 3 && riser?.toRank == 2)
        #expect(riser?.monthly.count == 4 && near(riser?.monthly.last?.value, 0.4) && near(riser?.monthly.first?.value, 0))
        #expect(riser?.monthly.first?.month == statsAt(2026, 7, 1, 0))
        #expect(cooled?.podcast.title == "A" && near(cooled?.fromShare, 0.6) && near(cooled?.toShare, 0.2))
        #expect(cooled?.fromRank == 1 && cooled?.toRank == 3)
    }

    @Test func cooledPodcastNoLongerHeardHasNoRank() {
        let records = earlier + month(2026, 10, [(b, 40), (c, 60)])
        let cooled = statsReport(statsOct, records).cooled
        #expect(cooled?.podcast.title == "A" && cooled?.toRank == nil && near(cooled?.toShare, 0))
    }

    @Test(arguments: [(share: 9.0, expected: false), (share: 10.0, expected: true)])
    func riserNeedsTenPercentagePoints(share: Double, expected: Bool) {
        // C gets `share` of 100 minutes; A and B split the rest.
        let records = earlier + month(2026, 10, [(a, (100 - share) / 2 + 1), (b, (100 - share) / 2 - 1), (c, share)])
        #expect((statsReport(statsOct, records).riser != nil) == expected)
    }

    @Test(arguments: [(months: 1, expected: false), (months: 2, expected: true)])
    func monthViewNeedsTwoComparisonMonths(months: Int, expected: Bool) {
        let records = (9 - months + 1 ... 9).flatMap { month(2026, $0, [(a, 60), (b, 40)]) } + month(2026, 10, [(a, 20), (b, 40), (c, 40)])
        let report = statsReport(statsOct, records)
        #expect((report.riser != nil) == expected && (report.cooled != nil) == expected)
    }

    // MARK: I30 / I31 year view

    private var halfYear: [ListeningRecord] {
        month(2026, 1, [(a, 80), (b, 20)]) + month(2026, 2, [(a, 80), (b, 20)]) + month(2026, 3, [(a, 50), (b, 50)])
            + month(2026, 4, [(a, 50), (b, 50)]) + month(2026, 5, [(a, 30), (b, 30), (c, 40)])
            + month(2026, 6, [(a, 30), (b, 30), (c, 40)])
    }

    @Test func riserAndCooledOverTheYear() {
        let report = statsReport(statsYear, halfYear)
        #expect(report.riser?.podcast.title == "C" && near(report.riser?.toShare, 0.4) && report.riser?.monthly.count == 6)
        #expect(report.cooled?.podcast.title == "A" && near(report.cooled?.fromShare, 0.8) && near(report.cooled?.toShare, 0.3))
    }

    @Test func yearViewNeedsThreeMonths() {
        let two = month(2026, 1, [(a, 80), (b, 20)]) + month(2026, 2, [(a, 30), (b, 30), (c, 40)])
        #expect(statsReport(statsYear, two).riser == nil && statsReport(statsYear, two).cooled == nil)
    }

    // MARK: I32

    @Test func playlistShiftHighlightsAFactorOfTwo() {
        let (p1, p2) = (PlaylistID(), PlaylistID())
        func split(_ month: Int, _ first: Double, _ second: Double) -> [ListeningRecord] {
            self.month(2026, month, [(a, first), (b, second)], playlists: [p1, p2])
        }
        let records = split(1, 80, 20) + split(2, 80, 20) + split(3, 60, 40) + split(4, 60, 40) + split(5, 40, 60) + split(6, 40, 60)
        let shift = statsReport(statsYear, records).playlistShift
        #expect(shift?.months.count == 6 && near(shift?.months[0].shares.first?.share, 0.8))
        #expect(shift?.highlight?.playlist == p2 && shift?.highlight?.since == statsAt(2026, 5, 1, 0) && near(shift?.highlight?.factor, 3))
        // 20 % → 30 %: grown by 1.5 only.
        let mild = split(1, 80, 20) + split(2, 75, 25) + split(3, 70, 30) + split(4, 70, 30)
        let mildShift = statsReport(statsYear, mild).playlistShift
        #expect(mildShift != nil && mildShift?.highlight == nil)
        #expect(statsReport(statsYear, split(1, 80, 20) + split(2, 60, 40)).playlistShift == nil)
    }

    @Test func aSmallPlaylistThatGrewIsNotNamed() {
        let (p1, p2) = (PlaylistID(), PlaylistID())
        func split(_ month: Int, _ first: Double, _ second: Double) -> [ListeningRecord] {
            self.month(2026, month, [(a, first), (b, second)], playlists: [p1, p2])
        }
        // 2 % → 8 %: four times as much, still small.
        let records = split(1, 98, 2) + split(2, 98, 2) + split(3, 95, 5) + split(4, 92, 8) + split(5, 92, 8) + split(6, 92, 8)
        #expect(statsReport(statsYear, records).playlistShift?.highlight == nil)
    }

    @Test func playlistShiftHasEveryPlaylistInEveryMonthInOneOrder() {
        let (p1, p2) = (PlaylistID(), PlaylistID())
        let records = month(2026, 1, [(a, 60)], playlists: [p1]) + month(2026, 2, [(a, 30), (b, 30)], playlists: [p1, p2])
            + month(2026, 3, [(b, 90)], playlists: [p2])
        let shift = statsReport(statsYear, records).playlistShift
        // P2 has more over the year, so it comes first everywhere, also with 0 in January.
        #expect(shift?.months.map { $0.shares.map(\.playlist) } == [[p2, p1], [p2, p1], [p2, p1]])
        #expect(shift?.months[0].shares[0].share == 0 && shift?.months[2].shares[1].share == 0)
    }

    // MARK: I33

    @Test(arguments: [(last: 1.29, expected: false), (last: 1.3, expected: true)])
    func speedTrendNeedsATenthOfChange(last: Double, expected: Bool) {
        let records = month(2026, 1, [(a, 60)], speed: 1.2) + month(2026, 2, [(a, 60)], speed: 1.25) + month(2026, 3, [(a, 60)], speed: last)
        let trend = statsReport(statsYear, records).speedTrend
        #expect((trend != nil) == expected)
        if expected { #expect(near(trend?.from.value, 1.2) && near(trend?.to.value, last) && trend?.monthly.count == 3) }
        #expect(statsReport(statsYear, Array(records.prefix(2))).speedTrend == nil)
    }

    // MARK: I34

    @Test func daytimeShiftComparesFirstAndLastHalf() {
        let records = month(2026, 1, [(a, 60)], hour: 8) + month(2026, 2, [(a, 60)], hour: 8)
            + month(2026, 3, [(a, 60)], hour: 20) + month(2026, 4, [(a, 60)], hour: 20)
        let shift = statsReport(statsYear, records).daytimeShift
        #expect(shift?.from == .morning && shift?.to == .evening)
        // Three months: the first against the last.
        #expect(statsReport(statsYear, Array(records.prefix(1) + records.suffix(2))).daytimeShift?.from == .morning)
        // Same part in both halves, or fewer than three months: nothing.
        let same = month(2026, 1, [(a, 60)], hour: 8) + month(2026, 2, [(a, 60)], hour: 9) + month(2026, 3, [(a, 60)], hour: 8)
        #expect(statsReport(statsYear, same).daytimeShift == nil)
        #expect(statsReport(statsYear, Array(records.prefix(2))).daytimeShift == nil)
    }

    // MARK: I35

    @Test func yearChaptersNameTheTopPodcastOfEveryMonth() {
        let records = month(2026, 1, [(a, 60), (b, 30)]) + month(2026, 3, [(b, 60), (a, 30)]) + month(2026, 4, [(c, 10)])
        let chapters = statsReport(statsYear, records).yearChapters
        #expect(chapters?.map(\.podcast.title) == ["A", "B", "C"])
        #expect(chapters?.map(\.month) == [statsAt(2026, 1, 1, 0), statsAt(2026, 3, 1, 0), statsAt(2026, 4, 1, 0)])
        #expect(statsReport(statsYear, Array(records.prefix(4))).yearChapters == nil)
    }

    // MARK: I36

    @Test func newVersusLoyalTopFive() {
        let s = (1 ... 6).map { StatsShow("S\($0)") }
        let n = (1 ... 2).map { StatsShow("N\($0)") }
        let previous = month(2025, 3, (0 ..< 6).map { (s[$0], Double(100 - $0 * 10)) })
        let current = month(2026, 3, [(s[0], 100), (s[1], 90), (n[0], 80), (n[1], 70), (s[5], 60), (s[2], 10)])
        let result = statsReport(statsYear, previous + current).newVsLoyal
        // S6 was heard last year but was not in the top 5 then.
        #expect(result?.newInTop == 2 && result?.loyal.map(\.title) == ["S1", "S2"])
        #expect(statsReport(statsYear, current).newVsLoyal == nil)
        #expect(statsReport(statsSep, previous + current).newVsLoyal == nil)
    }

    // MARK: Seed

    @Test func sameInputGivesTheSameVariants() {
        let records = month(2026, 9, [(a, 600)], speed: 1.5)
        let first = statsReport(statsSep, records), second = statsReport(statsSep, records)
        #expect(first == second)
    }
}
