import Foundation
import Testing
@testable import PodlistKit

// MARK: Fixtures shared by the ListeningStats*Tests files

/// Gregorian, Europe/Berlin, weeks start on Monday.
let statsCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
    calendar.firstWeekday = 2
    return calendar
}()

func statsAt(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0) -> Date {
    statsCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

/// Tuesday 20 October 2026, noon: the current period is October.
let statsNow = statsAt(2026, 10, 20, 12)
let statsSep = StatsPeriod.month(year: 2026, month: 9)
let statsOct = StatsPeriod.month(year: 2026, month: 10)
let statsYear = StatsPeriod.year(2026)

/// Proportional splits leave rounding noise.
func near(_ value: Double?, _ expected: Double, tolerance: Double = 1e-4) -> Bool {
    value.map { abs($0 - expected) <= tolerance } ?? false
}

struct StatsShow {
    let id = PodcastID()
    let title: String
    init(_ title: String) { self.title = title }

    func podcast(
        playlists: [PlaylistID] = [], categories: [String] = [], subscribedAt: Date = .distantPast,
        isSubscribed: Bool = true, published: [Date] = []
    ) -> StatsPodcast {
        StatsPodcast(
            id: id, title: title, playlists: playlists, categories: categories, subscribedAt: subscribedAt,
            isSubscribed: isSubscribed, episodesPublishedAt: published)
    }
}

/// One session of `minutes` of listening starting at `start`.
func statsRec(
    _ start: Date, minutes: Double, _ show: StatsShow, episode: EpisodeID = EpisodeID(), playlist: PlaylistID? = nil,
    speed: Double = 1, reason: ListeningEndReason = .paused, skippedForward: Double = 0,
    published: Date = .distantPast, duration: TimeInterval? = nil, title: String = ""
) -> ListeningRecord {
    let seconds = minutes * 60
    return ListeningRecord(
        startedAt: start, endedAt: start.addingTimeInterval(seconds), listenedSeconds: seconds, contentSeconds: seconds * speed,
        skippedForwardSeconds: skippedForward, endReason: reason, episode: episode, podcast: show.id, playlist: playlist,
        episodeTitle: title, podcastTitle: show.title, episodePublishedAt: published, episodeDuration: duration)
}

func statsReport(
    _ period: StatsPeriod, _ sessions: [ListeningRecord], library: StatsLibrary = StatsLibrary(), now: Date = statsNow
) -> StatsReport {
    ListeningStats.report(for: period, sessions: sessions, library: library, calendar: statsCalendar, now: now)
}

extension StatsReport {
    func pick<T>(_ extract: (Insight) -> T?) -> T? { insights.lazy.compactMap(extract).first }

    var totalTime: TotalTime? { pick { if case let .totalTime(v) = $0 { v } else { nil } } }
    var conversion: Conversion? { pick { if case let .conversion(v) = $0 { v } else { nil } } }
    var episodes: (finished: Int, started: Int)? { pick { if case let .episodes(f, s) = $0 { (f, s) } else { nil } } }
    var listeningDays: ListeningDays? { pick { if case let .listeningDays(v) = $0 { v } else { nil } } }
    var variety: (count: Int, tone: VarietyTone)? { pick { if case let .podcastVariety(c, t) = $0 { (c, t) } else { nil } } }
    var topPodcasts: [PodcastShare]? { pick { if case let .topPodcasts(v) = $0 { v } else { nil } } }
    var playlists: [PlaylistShare]? { pick { if case let .playlists(_, all) = $0 { all } else { nil } } }
    var favoritePlaylist: PlaylistShare? { pick { if case let .playlists(favorite, _) = $0 { favorite } else { nil } } }
    var genre: (name: String, share: Double)? { pick { if case let .genre(n, s) = $0 { (n, s) } else { nil } } }
    var marathon: Marathon? { pick { if case let .marathon(v) = $0 { v } else { nil } } }
    var faithful: Faithful? { pick { if case let .faithful(v) = $0 { v } else { nil } } }
    var binge: Binge? { pick { if case let .binge(v) = $0 { v } else { nil } } }
    var newDiscovery: NewDiscovery? { pick { if case let .newDiscovery(v) = $0 { v } else { nil } } }
    var recordDay: RecordDay? { pick { if case let .recordDay(v) = $0 { v } else { nil } } }
    var streak: Streak? { pick { if case let .streak(v) = $0 { v } else { nil } } }
    var longestBreak: (days: Int, start: Date)? { pick { if case let .longestBreak(d, s) = $0 { (d, s) } else { nil } } }
    var strongestStretch: StrongestStretch? { pick { if case let .strongestStretch(v) = $0 { v } else { nil } } }
    var heatmap: Heatmap? { pick { if case let .heatmap(v) = $0 { v } else { nil } } }
    var listenerType: ListenerProfile? { pick { if case let .listenerType(v) = $0 { v } else { nil } } }
    var favoriteWeekday: (weekday: Int, weekendShare: Double)? { pick { if case let .favoriteWeekday(w, s) = $0 { (w, s) } else { nil } } }
    var speed: Speed? { pick { if case let .speed(v) = $0 { v } else { nil } } }
    var skipped: TimeInterval? { pick { if case let .skipped(v) = $0 { v } else { nil } } }
    var completion: Completion? { pick { if case let .completion(v) = $0 { v } else { nil } } }
    var sleep: Sleep? { pick { if case let .sleep(v) = $0 { v } else { nil } } }
    var freshness: [PlaylistFreshness]? { pick { if case let .freshness(v) = $0 { v } else { nil } } }
    var archaeologist: EpisodeMoment? { pick { if case let .archaeologist(v) = $0 { v } else { nil } } }
    var quickest: (EpisodeMoment, delay: TimeInterval)? { pick { if case let .quickest(m, d) = $0 { (m, d) } else { nil } } }
    var repeated: (EpisodeMoment, times: Int)? { pick { if case let .repeated(m, t) = $0 { (m, t) } else { nil } } }
    var longestEpisode: (EpisodeMoment, duration: TimeInterval)? { pick { if case let .longestEpisode(m, d) = $0 { (m, d) } else { nil } } }
    var shortestEpisode: (EpisodeMoment, duration: TimeInterval)? { pick { if case let .shortestEpisode(m, d) = $0 { (m, d) } else { nil } } }
    var longHaul: (EpisodeMoment, days: Int)? { pick { if case let .longHaul(m, d) = $0 { (m, d) } else { nil } } }
    var nightShift: EpisodeMoment? { pick { if case let .nightShift(v) = $0 { v } else { nil } } }
    var firstAndLast: (first: EpisodeMoment, last: EpisodeMoment)? { pick { if case let .firstAndLast(f, l) = $0 { (f, l) } else { nil } } }
    var holidays: [HolidayListen]? { pick { if case let .holidays(v) = $0 { v } else { nil } } }
    var neglected: [NeglectedPodcast]? { pick { if case let .neglected(v) = $0 { v } else { nil } } }
    var backlog: Backlog? { pick { if case let .backlog(v) = $0 { v } else { nil } } }
    var unheardSubscriptions: Int? { pick { if case let .unheardSubscriptions(v) = $0 { v } else { nil } } }
    var trend: Trend? { pick { if case let .trend(v) = $0 { v } else { nil } } }
    var riser: ShareChange? { pick { if case let .riser(v) = $0 { v } else { nil } } }
    var cooled: ShareChange? { pick { if case let .cooled(v) = $0 { v } else { nil } } }
    var playlistShift: PlaylistShift? { pick { if case let .playlistShift(v) = $0 { v } else { nil } } }
    var speedTrend: SpeedTrend? { pick { if case let .speedTrend(v) = $0 { v } else { nil } } }
    var daytimeShift: (from: DayPart, to: DayPart)? { pick { if case let .daytimeShift(f, t) = $0 { (f, t) } else { nil } } }
    var yearChapters: [MonthTop]? { pick { if case let .yearChapters(v) = $0 { v } else { nil } } }
    var newVsLoyal: (newInTop: Int, loyal: [PodcastRef])? { pick { if case let .newVsLoyal(n, l) = $0 { (n, l) } else { nil } } }
}

// MARK: Basics, overview (I1–I5)

struct ListeningStatsTests {
    private let a = StatsShow("A")
    private let b = StatsShow("B")

    @Test func emptyLogAndEmptyPeriodGiveAnEmptyReport() {
        let empty = statsReport(statsSep, [])
        #expect(empty.isEmpty && empty.insights.isEmpty && empty.recordingStartedAt == nil)
        // Sessions only in another period.
        let other = statsReport(statsSep, [statsRec(statsAt(2026, 8, 3), minutes: 30, a)])
        #expect(other.isEmpty && other.insights.isEmpty)
    }

    @Test func recordingStartIsSetOnlyInThePeriodWhereTheLogBegins() {
        let sessions = [statsRec(statsAt(2026, 9, 12, 9), minutes: 30, a), statsRec(statsAt(2026, 10, 3, 9), minutes: 30, a)]
        #expect(statsReport(statsSep, sessions).recordingStartedAt == statsAt(2026, 9, 12, 9))
        #expect(statsReport(statsOct, sessions).recordingStartedAt == nil)
    }

    @Test func insightsKeepCatalogOrder() {
        // A rich month: the sections never go backwards.
        var sessions: [ListeningRecord] = []
        for day in 1 ... 12 {
            sessions.append(statsRec(statsAt(2026, 9, day, 8), minutes: 40, a, speed: 1.3))
            sessions.append(statsRec(statsAt(2026, 9, day, 18), minutes: 30, b, reason: .sleepTimer))
        }
        let report = statsReport(statsSep, sessions)
        #expect(report.insights.count > 10)
        let sections = report.insights.map(\.section.rawValue)
        #expect(sections == sections.sorted())
        #expect(report.totalTime != nil)
        if case .totalTime = report.insights.first {} else { Issue.record("I1 must come first") }
    }

    // MARK: Splitting

    @Test func aSessionOverMidnightIsSplitBetweenTheDays() {
        // 23:30 → 00:30 over 30 September / 1 October, 60 min listened.
        let session = statsRec(statsAt(2026, 9, 30, 23, 30), minutes: 60, a)
        #expect(near(statsReport(statsSep, [session]).listenedSeconds, 1_800))
        #expect(near(statsReport(statsOct, [session]).listenedSeconds, 1_800))
    }

    @Test func aSessionOverMidnightMovesTheRecordDay() {
        // 1 h on day 1; on day 2 the late session crosses midnight: 30 + 30 min.
        let sessions = [
            statsRec(statsAt(2026, 9, 10, 8), minutes: 50, a),
            statsRec(statsAt(2026, 9, 11, 23, 30), minutes: 60, b),
        ]
        let record = statsReport(statsSep, sessions).recordDay
        #expect(record?.day == statsAt(2026, 9, 10, 0))
        #expect(near(record?.seconds, 3_000))
    }

    @Test func zeroOrNegativeSpansCountFullyAtTheirStart() {
        let instant = ListeningRecord(
            startedAt: statsAt(2026, 9, 30, 23, 59), endedAt: statsAt(2026, 9, 30, 23, 59), listenedSeconds: 600,
            episode: EpisodeID(), podcast: a.id)
        #expect(statsReport(statsSep, [instant]).listenedSeconds == 600)
        #expect(statsReport(statsOct, [instant]).listenedSeconds == 0)
    }

    // MARK: I1

    @Test func totalTimeComparesWithThePreviousPeriod() {
        let sessions = [
            statsRec(statsAt(2026, 8, 1, 8), minutes: 600, a),
            statsRec(statsAt(2026, 9, 5, 8), minutes: 720, a, speed: 1.5),
        ]
        let total = statsReport(statsSep, sessions).totalTime
        #expect(near(total?.listenedSeconds, 720 * 60))
        #expect(near(total?.contentSeconds, 1_080 * 60))
        #expect(abs((total?.change ?? 0) - 0.2) < 1e-9)
        // August has no previous period with data, nor does the first month overall.
        #expect(statsReport(.month(year: 2026, month: 8), sessions).totalTime?.change == nil)
    }

    @Test func aRunningPeriodComparesTheSameSpan() {
        // 1–20 October (now) against 1–20 September; the rest of September does not count.
        let sessions = [
            statsRec(statsAt(2026, 9, 1, 8), minutes: 60, a),
            statsRec(statsAt(2026, 9, 25, 8), minutes: 600, a),
            statsRec(statsAt(2026, 10, 3, 8), minutes: 90, a),
        ]
        #expect(near(statsReport(statsOct, sessions).totalTime?.change, 0.5))
        // A year: 2026 up to 20 October against 2025 up to 20 October.
        let years = [
            statsRec(statsAt(2025, 1, 1, 8), minutes: 60, a), statsRec(statsAt(2025, 11, 1, 8), minutes: 600, a),
            statsRec(statsAt(2026, 2, 1, 8), minutes: 120, a),
        ]
        #expect(near(statsReport(statsYear, years).totalTime?.change, 1))
    }

    @Test func aHalfRecordedPreviousPeriodIsNotCompared() {
        // Recording started on 9 September: October is not compared with it.
        let sessions = [statsRec(statsAt(2026, 9, 9, 8), minutes: 600, a), statsRec(statsAt(2026, 10, 3, 8), minutes: 60, a)]
        #expect(statsReport(statsOct, sessions).totalTime != nil)
        #expect(statsReport(statsOct, sessions).totalTime?.change == nil)
    }

    // MARK: I2

    @Test(arguments: [
        (minutes: 59.0, unit: nil as ConversionUnit?, count: 0),
        (minutes: 180.0, unit: .footballMatch as ConversionUnit?, count: 2),
    ])
    func conversionNeedsAnHourAndASizeThatFits(minutes: Double, unit: ConversionUnit?, count: Int) {
        let conversion = statsReport(statsSep, [statsRec(statsAt(2026, 9, 5, 8), minutes: minutes, a)]).conversion
        #expect(conversion?.unit == unit)
        if unit != nil { #expect(conversion?.count == count) }
    }

    @Test func conversionVariantComesFromThePeriodSeed() {
        // 10 h: ISS 6, football 6, movie 5, marathon 4 → seed % 4.
        func conversion(_ period: StatsPeriod, month: Int) -> Conversion? {
            statsReport(period, [statsRec(statsAt(2026, month, 5, 8), minutes: 600, a)]).conversion
        }
        #expect(conversion(statsSep, month: 9) == Conversion(unit: .footballMatch, count: 6))
        #expect(conversion(statsOct, month: 10) == Conversion(unit: .movie, count: 5))
        #expect(conversion(statsSep, month: 9) == conversion(statsSep, month: 9))
    }

    // MARK: I3

    @Test func finishedAndStartedEpisodes() {
        let done = EpisodeID(), half = EpisodeID(), twice = EpisodeID()
        let sessions = [
            statsRec(statsAt(2026, 9, 5, 8), minutes: 30, a, episode: done),
            statsRec(statsAt(2026, 9, 5, 9), minutes: 5, a, episode: done, reason: .finished),
            statsRec(statsAt(2026, 9, 6, 8), minutes: 30, a, episode: half),
            statsRec(statsAt(2026, 9, 7, 8), minutes: 10, b, episode: twice),
            statsRec(statsAt(2026, 9, 8, 8), minutes: 10, b, episode: twice),
        ]
        let episodes = statsReport(statsSep, sessions).episodes
        #expect(episodes?.finished == 1 && episodes?.started == 2)
    }

    @Test func anEpisodeFinishedInAnotherMonthIsOnlyStartedHere() {
        let episode = EpisodeID()
        let sessions = [
            statsRec(statsAt(2026, 9, 5, 8), minutes: 30, a, episode: episode),
            statsRec(statsAt(2026, 10, 2, 8), minutes: 30, a, episode: episode, reason: .finished),
        ]
        #expect(statsReport(statsSep, sessions).episodes?.started == 1)
        #expect(statsReport(statsSep, sessions).episodes?.finished == 0)
        #expect(statsReport(statsOct, sessions).episodes?.finished == 1)
    }

    // MARK: I4

    @Test(arguments: [(days: 2, expected: false), (days: 3, expected: true)])
    func listeningDaysNeedThreeDays(days: Int, expected: Bool) {
        let sessions = (1 ... days).map { statsRec(statsAt(2026, 9, $0, 8), minutes: 60, a) }
        let result = statsReport(statsSep, sessions).listeningDays
        #expect((result != nil) == expected)
        if expected {
            #expect(result?.days == 3 && result?.daysInPeriod == 30 && near(result?.averagePerDay, 3_600))
        }
    }

    @Test func daysInTheCurrentPeriodStopAtToday() {
        let sessions = (1 ... 3).map { statsRec(statsAt(2026, 10, $0, 8), minutes: 60, a) }
        #expect(statsReport(statsOct, sessions).listeningDays?.daysInPeriod == 20)
    }

    @Test func daysBeforeRecordingStartedDoNotCount() {
        // Recording started on 9 October (plan §6.3): 12 days up to today, not 20.
        let sessions = (9 ... 11).map { statsRec(statsAt(2026, 10, $0, 8), minutes: 60, a) }
        let report = statsReport(statsOct, sessions)
        #expect(report.listeningDays?.daysInPeriod == 12)
        #expect(report.recordingStartedAt == statsAt(2026, 10, 9, 8))
    }

    // MARK: I5

    @Test(arguments: [
        (count: 1, tone: nil as VarietyTone?), (count: 2, tone: .focused as VarietyTone?), (count: 3, tone: .focused as VarietyTone?),
        (count: 4, tone: .balanced as VarietyTone?), (count: 9, tone: .balanced as VarietyTone?),
        (count: 10, tone: .explorer as VarietyTone?),
    ])
    func varietyTone(count: Int, tone: VarietyTone?) {
        let sessions = (0 ..< count).map { statsRec(statsAt(2026, 9, 5, 8 + $0), minutes: 20, StatsShow("P\($0)")) }
        let variety = statsReport(statsSep, sessions).variety
        #expect(variety?.tone == tone)
        if tone != nil { #expect(variety?.count == count) }
    }
}
