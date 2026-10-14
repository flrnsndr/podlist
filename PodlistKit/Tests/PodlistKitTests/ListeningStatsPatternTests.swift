import Foundation
import Testing
@testable import PodlistKit

// D. Rhythm (I17–I19) and E. Style (I20–I24).
struct ListeningStatsPatternTests {
    private let a = StatsShow("A")
    private let b = StatsShow("B")
    private let c = StatsShow("C")

    /// Sessions as (day of September 2026, start hour, minutes). 5 and 6 are Saturday and Sunday,
    /// 7…11 Monday to Friday.
    private func sessions(_ entries: [(day: Int, hour: Int, minutes: Double)], speed: Double = 1) -> [ListeningRecord] {
        entries.map { statsRec(statsAt(2026, 9, $0.day, $0.hour), minutes: $0.minutes, a, speed: speed) }
    }

    private static let workdays = [7, 8, 9, 10, 11]
    private static func daily(_ hours: [Int], minutes: Double = 60) -> [(day: Int, hour: Int, minutes: Double)] {
        workdays.flatMap { day in hours.map { (day: day, hour: $0, minutes: minutes) } }
    }

    // MARK: I17

    @Test(arguments: [
        (days: 4, minutes: 75.0, expected: false), // 5 h but 4 days
        (days: 5, minutes: 59.0, expected: false), // 5 days but 4 h 55 min
        (days: 5, minutes: 60.0, expected: true),
    ])
    func rhythmNeedsFiveHoursAndFiveDays(days: Int, minutes: Double, expected: Bool) {
        let entries = Self.workdays.prefix(days).map { (day: $0, hour: 9, minutes: minutes) }
        let report = statsReport(statsSep, sessions(entries))
        #expect((report.heatmap != nil) == expected)
        #expect((report.listenerType != nil) == expected)
    }

    @Test func heatmapSplitsOverHourBoundaries() {
        // Tuesday 8 Sep 08:30–09:30 plus four more days for the condition.
        var entries = Self.workdays.filter { $0 != 8 }.map { (day: $0, hour: 12, minutes: 60.0) }
        entries.append((day: 8, hour: 8, minutes: 60))
        let session = statsRec(statsAt(2026, 9, 8, 8, 30), minutes: 60, a)
        let heatmap = statsReport(statsSep, sessions(entries.dropLast()) + [session]).heatmap
        #expect(near(heatmap?.seconds[2][8], 1_800) && near(heatmap?.seconds[2][9], 1_800))
        // Monday has index 1 (weekday 2); Tuesday's noon is empty.
        #expect(near(heatmap?.seconds[1][12], 3_600) && near(heatmap?.seconds[4][12], 3_600))
        #expect(near(heatmap?.seconds[2][12], 0))
    }

    @Test func heatmapAcrossTheDaylightSavingChange() {
        // Last Sunday of October 2026 is the 25th: 01:30 CEST → 03:30 CET is 3 h of wall-clock time.
        let night = statsRec(statsAt(2026, 10, 25, 1, 30), minutes: 0, a)
        var long = night
        long.endedAt = statsAt(2026, 10, 25, 3, 30)
        long.listenedSeconds = 3 * 3_600
        long.contentSeconds = 3 * 3_600
        let others = (26 ... 29).map { statsRec(statsAt(2026, 10, $0, 12), minutes: 60, a) }
        let report = statsReport(statsOct, [long] + others, now: statsAt(2026, 11, 3, 12))
        let sunday = report.heatmap?.seconds[0]
        #expect(near(sunday?[1], 1_800) && near(sunday?[2], 7_200) && near(sunday?[3], 1_800))
        #expect(report.listeningDays?.days == 5)
    }

    @Test(arguments: [
        // weekend mornings beat weekday afternoons
        (weekend: true, part: DayPart.morning),
        (weekend: false, part: DayPart.afternoon),
    ])
    func heatmapPeakIsNormalizedByDaysAndHours(weekend: Bool, part: DayPart) {
        let entries: [(day: Int, hour: Int, minutes: Double)] = weekend
            ? [(5, 8, 120), (6, 8, 120), (7, 16, 60), (8, 16, 60), (9, 16, 60)]
            : Self.daily([7, 17])
        let heatmap = statsReport(statsSep, sessions(entries)).heatmap
        #expect(heatmap?.peakIsWeekend == weekend && heatmap?.peakPart == part)
    }

    // MARK: I18

    struct RhythmRow: Sendable, CustomTestStringConvertible {
        var label: String
        var entries: [(day: Int, hour: Int, minutes: Double)]
        var type: ListenerType
        var share: Double
        var spice: ListenerSpice?
        var testDescription: String { label }
    }

    private static let rows: [RhythmRow] = [
        RhythmRow(label: "commuter", entries: daily([7, 17]), type: .commuter, share: 1),
        RhythmRow(label: "night owl", entries: daily([23]), type: .nightOwl, share: 1),
        RhythmRow(label: "early bird", entries: daily([5]), type: .earlyBird, share: 1),
        RhythmRow(
            label: "weekender", entries: [(5, 10, 120), (6, 10, 120), (7, 16, 60), (8, 16, 60), (9, 16, 60)],
            type: .weekender, share: 4.0 / 7, spice: .stamina),
        RhythmRow(label: "lunch break", entries: daily([12]), type: .lunchBreak, share: 1),
        RhythmRow(label: "after work", entries: daily([19]), type: .afterWork, share: 1),
        RhythmRow(label: "all-rounder", entries: daily([10]), type: .allRounder, share: 1),
        // Commute pattern with a heavy Saturday: weekend 33 % ≥ 20 %, so not a commuter; 7 o'clock is early bird.
        RhythmRow(
            label: "commuter falls through", entries: daily([7, 17]) + [(5, 10, 300)], type: .earlyBird, share: 5.0 / 15,
            spice: .stamina),
    ]

    @Test(arguments: rows)
    func listenerTypes(_ row: RhythmRow) {
        let profile = statsReport(statsSep, sessions(row.entries)).listenerType
        #expect(profile?.type == row.type)
        #expect(near(profile?.share, row.share, tolerance: 1e-6))
        #expect(profile?.spice == row.spice)
    }

    @Test(arguments: [
        (label: "fast", speed: 1.5, reasons: [ListeningEndReason.paused], stamina: false, spice: ListenerSpice?.some(.fast)),
        (label: "just not fast", speed: 1.49, reasons: [.paused], stamina: false, spice: nil),
        (label: "stamina", speed: 1.0, reasons: [.paused], stamina: true, spice: .stamina),
        (label: "sleeper 1 of 5", speed: 1.0, reasons: [.sleepTimer, .paused, .paused, .paused, .paused], stamina: false, spice: .sleeper),
        (label: "sleeper 1 of 6", speed: 1.0, reasons: [.sleepTimer, .paused, .paused, .paused, .paused, .paused], stamina: false, spice: nil),
        (label: "fast beats sleeper", speed: 1.5, reasons: [.sleepTimer, .paused, .paused, .paused, .paused], stamina: false, spice: .fast),
    ])
    func listenerSpice(label: String, speed: Double, reasons: [ListeningEndReason], stamina: Bool, spice: ListenerSpice?) {
        var records: [ListeningRecord] = []
        for index in 0 ..< max(5, reasons.count) {
            let day = Self.workdays[index % 5]
            let reason = index < reasons.count ? reasons[index] : .paused
            records.append(statsRec(statsAt(2026, 9, day, 10 + index / 5 * 2), minutes: 60, a, speed: speed, reason: reason))
        }
        if stamina {
            // Two back-to-back hours of one episode on the first day.
            let episode = EpisodeID()
            records = Self.workdays.map { statsRec(statsAt(2026, 9, $0, 10), minutes: 60, a) }
            records.append(statsRec(statsAt(2026, 9, 7, 11), minutes: 60, a, episode: episode))
            records[0] = statsRec(statsAt(2026, 9, 7, 10), minutes: 60, a, episode: episode)
        }
        #expect(statsReport(statsSep, records).listenerType?.spice == spice)
    }

    // MARK: I19

    @Test func favoriteWeekdayAndWeekendShare() {
        let records = [
            statsRec(statsAt(2026, 9, 8, 9), minutes: 120, a), statsRec(statsAt(2026, 9, 15, 9), minutes: 60, a),
            statsRec(statsAt(2026, 9, 12, 9), minutes: 60, a),
        ]
        let result = statsReport(statsSep, records).favoriteWeekday
        #expect(result?.weekday == 3 && near(result?.weekendShare, 0.25))
        // One calendar week only.
        let oneWeek = [records[0], statsRec(statsAt(2026, 9, 9, 9), minutes: 60, a)]
        #expect(statsReport(statsSep, oneWeek).favoriteWeekday == nil)
    }

    // MARK: I20

    @Test(arguments: [
        (speed: 1.04, expected: false), (speed: 1.05, expected: true), (speed: 0.96, expected: false), (speed: 0.95, expected: true),
    ])
    func speedNeedsADifferenceOfFivePercent(speed: Double, expected: Bool) {
        let result = statsReport(statsSep, [statsRec(statsAt(2026, 9, 5, 8), minutes: 60, a, speed: speed)]).speed
        #expect((result != nil) == expected)
        if expected && speed < 1 { #expect(result?.conversion == nil && result!.savedSeconds < 0) }
    }

    @Test func speedConversionComesFromTheSeed() {
        // 10 h at 1.5× saves 5 h: nap 15, pasta 25, washing cycle 3 → seed % 3.
        func speed(_ period: StatsPeriod, month: Int) -> Speed? {
            statsReport(period, [statsRec(statsAt(2026, month, 5, 8), minutes: 600, a, speed: 1.5)]).speed
        }
        #expect(near(speed(statsSep, month: 9)?.average, 1.5) && near(speed(statsSep, month: 9)?.savedSeconds, 18_000))
        #expect(speed(statsSep, month: 9)?.conversion == Conversion(unit: .pastaCooking, count: 25))
        #expect(speed(statsOct, month: 10)?.conversion == Conversion(unit: .washingCycle, count: 3))
    }

    // MARK: I21

    @Test(arguments: [(seconds: 599.0, expected: false), (seconds: 600.0, expected: true)])
    func skippedNeedsTenMinutes(seconds: Double, expected: Bool) {
        let records = [
            statsRec(statsAt(2026, 9, 5, 8), minutes: 30, a, skippedForward: seconds - 100),
            statsRec(statsAt(2026, 9, 6, 8), minutes: 30, a, skippedForward: 100),
        ]
        #expect((statsReport(statsSep, records).skipped != nil) == expected)
        if expected { #expect(statsReport(statsSep, records).skipped == 600) }
    }

    // MARK: I22

    private func completionSessions(episodes: Int, finished: Int) -> [ListeningRecord] {
        (0 ..< episodes).map {
            statsRec(statsAt(2026, 10, 2 + $0, 8), minutes: 20, a, reason: $0 < finished ? .finished : .paused)
        }
    }

    @Test(arguments: [(episodes: 4, expected: false), (episodes: 5, expected: true)])
    func completionNeedsFiveEpisodes(episodes: Int, expected: Bool) {
        let completion = statsReport(statsOct, completionSessions(episodes: episodes, finished: 3)).completion
        #expect((completion != nil) == expected)
        if expected { #expect(near(completion?.rate, 0.6)) }
    }

    @Test func lingeringEpisodeIsTheOneStartedLongestAgoAtLeastTwoWeeks() {
        let old = EpisodeID(), recent = EpisodeID()
        var records = completionSessions(episodes: 5, finished: 3)
        records.append(statsRec(statsAt(2026, 10, 1, 8), minutes: 10, a, episode: old))
        records.append(statsRec(statsAt(2026, 10, 8, 8), minutes: 10, a, episode: recent))
        records.append(statsRec(statsAt(2026, 10, 15, 8), minutes: 10, a, episode: old))
        let inProgress = [
            StatsInProgressEpisode(id: recent, title: "Recent", podcastTitle: "A", position: 100),
            StatsInProgressEpisode(id: old, title: "Old", podcastTitle: "A", position: 200),
        ]
        let library = StatsLibrary(inProgress: inProgress)
        let lingering = statsReport(statsOct, records, library: library).completion?.lingering
        #expect(lingering?.episode == old && lingering?.since == statsAt(2026, 10, 1, 8) && lingering?.position == 200)
        // Only the episode started 12 days ago: too fresh.
        let fresh = StatsLibrary(inProgress: [inProgress[0]])
        #expect(statsReport(statsOct, records, library: fresh).completion?.lingering == nil)
        // Not the current period: no lingering.
        let later = statsReport(statsOct, records, library: library, now: statsAt(2026, 11, 20)).completion
        #expect(later != nil && later?.lingering == nil)
    }

    // MARK: I23

    @Test(arguments: [(count: 2, expected: false), (count: 3, expected: true)])
    func sleepNeedsThreeSessions(count: Int, expected: Bool) {
        var records = [statsRec(statsAt(2026, 9, 5, 22), minutes: 30, a, reason: .sleepTimer)]
        records += [statsRec(statsAt(2026, 9, 6, 22), minutes: 30, a, reason: .sleepTimer)]
        records += [statsRec(statsAt(2026, 9, 7, 22), minutes: 30, b, reason: .sleepTimer)]
        records += [statsRec(statsAt(2026, 9, 8, 22), minutes: 30, b, reason: .paused)]
        let sleep = statsReport(statsSep, Array(records.prefix(count) + records.suffix(1))).sleep
        #expect((sleep != nil) == expected)
        if expected { #expect(sleep?.count == 3 && sleep?.podcast.title == "A" && sleep?.podcastCount == 2) }
    }

    // MARK: I24

    private func fresh(
        _ show: StatsShow, day: Int, delay: TimeInterval, episode: EpisodeID = EpisodeID(), month: Int = 9
    ) -> ListeningRecord {
        let start = statsAt(2026, month, day, 9)
        return statsRec(start, minutes: 20, show, episode: episode, published: start.addingTimeInterval(-delay))
    }

    @Test func freshnessIsTheMedianDelayPerPlaylist() {
        let (p1, p2) = (PlaylistID(), PlaylistID())
        let library = StatsLibrary(
            podcasts: [a.podcast(playlists: [p1]), b.podcast(playlists: [p2, p1])],
            playlists: [StatsPlaylist(id: p1, name: "P1"), StatsPlaylist(id: p2, name: "P2")])
        let day = 86_400.0
        let records = [
            fresh(a, day: 5, delay: 1 * day), fresh(a, day: 6, delay: 3 * day), fresh(a, day: 7, delay: 5 * day),
            fresh(b, day: 8, delay: 40 * day), fresh(b, day: 9, delay: 50 * day),
            // One episode on its own: no row of its own; unpublished and "from the future" episodes are skipped.
            fresh(c, day: 10, delay: day),
            statsRec(statsAt(2026, 9, 11, 9), minutes: 20, a),
            fresh(a, day: 12, delay: -day),
        ]
        let rows = statsReport(statsSep, records, library: library).freshness
        // P1: A (1, 3, 5 d) and B (40, 50 d) → median 5 d; P2: B → 45 d; "Ohne Playlist": only one episode.
        #expect(rows?.map(\.playlist) == [p1, p2])
        #expect(near(rows?[0].median, 5 * day) && near(rows?[1].median, 45 * day))
    }

    @Test func freshnessNeedsFiveEpisodesAndOnlyCountsFirstListening() {
        let day = 86_400.0
        let four = [
            fresh(a, day: 5, delay: day), fresh(a, day: 6, delay: day), fresh(b, day: 7, delay: day), fresh(b, day: 8, delay: day),
        ]
        #expect(statsReport(statsSep, four).freshness == nil)
        // A fifth episode that was already heard in August is not "first heard" in September.
        let heardBefore = EpisodeID()
        let five = four + [fresh(b, day: 9, delay: day, episode: heardBefore), fresh(b, day: 20, delay: day, episode: heardBefore, month: 8)]
        #expect(statsReport(statsSep, five).freshness == nil)
        #expect(statsReport(statsSep, four + [fresh(b, day: 9, delay: day)]).freshness?.count == 1)
    }
}
