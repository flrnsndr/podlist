import Foundation

// Input and output of `ListeningStats` (concept §4.11, plan-hoerstatistik §5–§6). The
// service turns the listening log and the library into these values; the app turns the
// insights into cards. The domain decides which insight shows, its tone and its comparison,
// so all of that is testable without comparing texts.

// MARK: Period

/// A calendar month or year in the device calendar (plan §11: no "last 30 days").
public enum StatsPeriod: Hashable, Sendable {
    case month(year: Int, month: Int)
    case year(Int)

    public enum Kind: String, Hashable, Sendable, CaseIterable {
        case month
        case year
    }

    public var kind: Kind {
        switch self {
        case .month: .month
        case .year: .year
        }
    }

    /// The period of `kind` that contains `date`.
    public init(_ kind: Kind, containing date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        switch kind {
        case .month: self = .month(year: parts.year!, month: parts.month!)
        case .year: self = .year(parts.year!)
        }
    }

    /// Start (inclusive) to end (exclusive).
    public func interval(in calendar: Calendar) -> DateInterval {
        let start: Date
        let end: Date
        switch self {
        case let .month(year, month):
            start = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
            end = calendar.date(byAdding: .month, value: 1, to: start)!
        case let .year(year):
            start = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
            end = calendar.date(byAdding: .year, value: 1, to: start)!
        }
        return DateInterval(start: start, end: end)
    }

    /// The period of the same kind before this one (October → September, 2026 → 2025).
    public var previous: StatsPeriod {
        switch self {
        case let .month(year, month): month == 1 ? .month(year: year - 1, month: 12) : .month(year: year, month: month - 1)
        case let .year(year): .year(year - 1)
        }
    }

    public var next: StatsPeriod {
        switch self {
        case let .month(year, month): month == 12 ? .month(year: year + 1, month: 1) : .month(year: year, month: month + 1)
        case let .year(year): .year(year + 1)
        }
    }

    /// Fixed per period: where an insight has variants (conversions, quips), the same
    /// view always shows the same one and the share card matches the page (plan §5).
    public var seed: UInt64 {
        switch self {
        case let .month(year, month): UInt64(year * 100 + month)
        case let .year(year): UInt64(year * 100)
        }
    }

    /// Sort key: months and years each in calendar order.
    var ordinal: Int {
        switch self {
        case let .month(year, month): year * 12 + month
        case let .year(year): year
        }
    }
}

extension StatsPeriod: Comparable {
    public static func < (lhs: StatsPeriod, rhs: StatsPeriod) -> Bool { lhs.ordinal < rhs.ordinal }
}

// MARK: Input

/// One stored `ListeningSession` as a value (plan §3).
public struct ListeningRecord: Hashable, Sendable {
    public var startedAt: Date
    public var endedAt: Date
    /// Wall-clock seconds the episode was playing ("Lebenszeit").
    public var listenedSeconds: TimeInterval
    /// Episode seconds that went by ("Folgenzeit").
    public var contentSeconds: TimeInterval
    public var skippedForwardSeconds: TimeInterval
    public var skippedBackwardSeconds: TimeInterval
    public var startPosition: TimeInterval
    public var endPosition: TimeInterval
    public var endReason: ListeningEndReason
    public var episode: EpisodeID
    /// `nil` for an episode without a podcast (never in practice).
    public var podcast: PodcastID?
    /// The playlist block it played in; `nil` = a single episode.
    public var playlist: PlaylistID?
    public var episodeTitle: String
    public var podcastTitle: String
    public var episodePublishedAt: Date
    public var episodeDuration: TimeInterval?

    public init(
        startedAt: Date, endedAt: Date, listenedSeconds: TimeInterval, contentSeconds: TimeInterval? = nil,
        skippedForwardSeconds: TimeInterval = 0, skippedBackwardSeconds: TimeInterval = 0,
        startPosition: TimeInterval = 0, endPosition: TimeInterval = 0, endReason: ListeningEndReason = .paused,
        episode: EpisodeID, podcast: PodcastID?, playlist: PlaylistID? = nil,
        episodeTitle: String = "", podcastTitle: String = "",
        episodePublishedAt: Date = .distantPast, episodeDuration: TimeInterval? = nil
    ) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.listenedSeconds = listenedSeconds
        self.contentSeconds = contentSeconds ?? listenedSeconds
        self.skippedForwardSeconds = skippedForwardSeconds
        self.skippedBackwardSeconds = skippedBackwardSeconds
        self.startPosition = startPosition
        self.endPosition = endPosition
        self.endReason = endReason
        self.episode = episode
        self.podcast = podcast
        self.playlist = playlist
        self.episodeTitle = episodeTitle
        self.podcastTitle = podcastTitle
        self.episodePublishedAt = episodePublishedAt
        self.episodeDuration = episodeDuration
    }
}

/// The library as it is now (plan §5). Past periods use today's playlists and
/// subscriptions; sessions of podcasts that are gone still count with their stored titles.
public struct StatsLibrary: Hashable, Sendable {
    public var podcasts: [StatsPodcast]
    public var playlists: [StatsPlaylist]
    /// Remaining duration of all unplayed episodes in playlists, in episode time (I27).
    public var backlogSeconds: TimeInterval
    /// Started, unplayed episodes (I22: the one lying around the longest).
    public var inProgress: [StatsInProgressEpisode]

    public init(
        podcasts: [StatsPodcast] = [], playlists: [StatsPlaylist] = [], backlogSeconds: TimeInterval = 0,
        inProgress: [StatsInProgressEpisode] = []
    ) {
        self.podcasts = podcasts
        self.playlists = playlists
        self.backlogSeconds = backlogSeconds
        self.inProgress = inProgress
    }
}

public struct StatsPodcast: Hashable, Sendable {
    public var id: PodcastID
    public var title: String
    /// The playlists it is assigned to (its "tags").
    public var playlists: [PlaylistID]
    /// iTunes categories, most specific first as stored; the first one is its genre (I8).
    public var categories: [String]
    public var subscribedAt: Date
    public var isSubscribed: Bool
    /// When its episodes were published (I26: new episodes in the period).
    public var episodesPublishedAt: [Date]

    public init(
        id: PodcastID, title: String, playlists: [PlaylistID] = [], categories: [String] = [],
        subscribedAt: Date = .distantPast, isSubscribed: Bool = true, episodesPublishedAt: [Date] = []
    ) {
        self.id = id
        self.title = title
        self.playlists = playlists
        self.categories = categories
        self.subscribedAt = subscribedAt
        self.isSubscribed = isSubscribed
        self.episodesPublishedAt = episodesPublishedAt
    }
}

public struct StatsPlaylist: Hashable, Sendable {
    public var id: PlaylistID
    public var name: String
    public var colorKey: String
    public var symbolName: String

    public init(id: PlaylistID, name: String, colorKey: String = "", symbolName: String = "") {
        self.id = id
        self.name = name
        self.colorKey = colorKey
        self.symbolName = symbolName
    }
}

public struct StatsInProgressEpisode: Hashable, Sendable {
    public var id: EpisodeID
    public var title: String
    public var podcastTitle: String
    public var position: TimeInterval

    public init(id: EpisodeID, title: String, podcastTitle: String, position: TimeInterval) {
        self.id = id
        self.title = title
        self.podcastTitle = podcastTitle
        self.position = position
    }
}

// MARK: Output

public struct StatsReport: Hashable, Sendable {
    public var period: StatsPeriod
    /// Sum of listening in the period; 0 = the empty page (plan §6.3).
    public var listenedSeconds: TimeInterval
    /// Set when recording started inside this period ("Aufgezeichnet seit …", plan §6.3).
    public var recordingStartedAt: Date?
    /// Only the insights whose condition holds, in catalog order (plan §6.3).
    public var insights: [Insight]

    public init(period: StatsPeriod, listenedSeconds: TimeInterval = 0, recordingStartedAt: Date? = nil, insights: [Insight] = []) {
        self.period = period
        self.listenedSeconds = listenedSeconds
        self.recordingStartedAt = recordingStartedAt
        self.insights = insights
    }

    public var isEmpty: Bool { listenedSeconds <= 0 }
}

/// The catalog's groups A–H, in page order (plan §6).
public enum InsightSection: Int, Hashable, Sendable, CaseIterable {
    case overview, favorites, records, rhythm, style, finds, conscience, trends
}

/// One card. Numbers in comments are the catalog IDs (plan §6).
public enum Insight: Hashable, Sendable {
    // A. Overview
    case totalTime(TotalTime)                          // I1
    case conversion(Conversion)                        // I2
    case episodes(finished: Int, started: Int)         // I3
    case listeningDays(ListeningDays)                  // I4
    case podcastVariety(count: Int, tone: VarietyTone) // I5
    // B. Favorites
    case topPodcasts([PodcastShare])                   // I6
    case playlists(favorite: PlaylistShare, all: [PlaylistShare]) // I7
    case genre(name: String, share: Double)            // I8
    case marathon(Marathon)                            // I9
    case faithful(Faithful)                            // I10
    case binge(Binge)                                  // I11
    case newDiscovery(NewDiscovery)                    // I12
    // C. Records
    case recordDay(RecordDay)                          // I13
    case streak(Streak)                                // I14
    case longestBreak(days: Int, start: Date)          // I15
    case strongestStretch(StrongestStretch)            // I16
    // D. Rhythm
    case heatmap(Heatmap)                              // I17
    case listenerType(ListenerProfile)                 // I18
    case favoriteWeekday(weekday: Int, weekendShare: Double) // I19
    // E. Style
    case speed(Speed)                                  // I20
    case skipped(seconds: TimeInterval)                // I21
    case completion(Completion)                        // I22
    case sleep(Sleep)                                  // I23
    case freshness([PlaylistFreshness])                // I24
    // F. Finds
    case archaeologist(EpisodeMoment)                  // I25
    case quickest(EpisodeMoment, delay: TimeInterval)  // I37
    case repeated(EpisodeMoment, times: Int)           // I38
    case longestEpisode(EpisodeMoment, duration: TimeInterval) // I39
    case shortestEpisode(EpisodeMoment, duration: TimeInterval) // I40
    case longHaul(EpisodeMoment, days: Int)            // I41
    case nightShift(EpisodeMoment)                     // I42
    case firstAndLast(first: EpisodeMoment, last: EpisodeMoment) // I43
    case holidays([HolidayListen])                     // I44
    // G. Conscience
    case neglected([NeglectedPodcast])                 // I26
    case backlog(Backlog)                              // I27
    case unheardSubscriptions(count: Int)              // I28
    // H. Trends
    case trend(Trend)                                  // I29
    case riser(ShareChange)                            // I30
    case cooled(ShareChange)                           // I31
    case playlistShift(PlaylistShift)                  // I32
    case speedTrend(SpeedTrend)                        // I33
    case daytimeShift(from: DayPart, to: DayPart)      // I34
    case yearChapters([MonthTop])                      // I35
    case newVsLoyal(newInTop: Int, loyal: [PodcastRef]) // I36

    public var section: InsightSection {
        switch self {
        case .totalTime, .conversion, .episodes, .listeningDays, .podcastVariety: .overview
        case .topPodcasts, .playlists, .genre, .marathon, .faithful, .binge, .newDiscovery: .favorites
        case .recordDay, .streak, .longestBreak, .strongestStretch: .records
        case .heatmap, .listenerType, .favoriteWeekday: .rhythm
        case .speed, .skipped, .completion, .sleep, .freshness: .style
        case .archaeologist, .quickest, .repeated, .longestEpisode, .shortestEpisode, .longHaul, .nightShift,
             .firstAndLast, .holidays: .finds
        case .neglected, .backlog, .unheardSubscriptions: .conscience
        case .trend, .riser, .cooled, .playlistShift, .speedTrend, .daytimeShift, .yearChapters, .newVsLoyal: .trends
        }
    }
}

// MARK: Insight values

/// A podcast as the statistics know it: the id (if it had one) and the stored title.
public struct PodcastRef: Hashable, Sendable {
    public var id: PodcastID?
    public var title: String

    public init(id: PodcastID?, title: String) {
        self.id = id
        self.title = title
    }
}

/// An episode at a moment (when it was heard, or when it was published for I25).
public struct EpisodeMoment: Hashable, Sendable {
    public var episode: EpisodeID
    public var title: String
    public var podcast: PodcastRef
    public var date: Date

    public init(episode: EpisodeID, title: String, podcast: PodcastRef, date: Date) {
        self.episode = episode
        self.title = title
        self.podcast = podcast
        self.date = date
    }
}

/// I1. `change` is relative to the previous period (0.23 = 23 % more), `nil` when that
/// period has no data.
public struct TotalTime: Hashable, Sendable {
    public var listenedSeconds: TimeInterval
    public var contentSeconds: TimeInterval
    public var change: Double?

    public init(listenedSeconds: TimeInterval, contentSeconds: TimeInterval, change: Double?) {
        self.listenedSeconds = listenedSeconds
        self.contentSeconds = contentSeconds
        self.change = change
    }
}

/// Everyday sizes (plan §6.2).
public enum ConversionUnit: String, Hashable, Sendable, CaseIterable {
    case pastaCooking, nap, footballMatch, washingCycle, issOrbit, movie, marathonWorldRecord
    case trainHamburgMunich, workday, nightOfSleep, flightFrankfurtNewYork, weekend

    public var seconds: TimeInterval {
        switch self {
        case .pastaCooking: 12 * 60
        case .nap: 20 * 60
        case .footballMatch, .washingCycle: 90 * 60
        case .issOrbit: 92 * 60
        case .movie: 2 * 3_600
        case .marathonWorldRecord: 2 * 3_600 + 60
        case .trainHamburgMunich: 6 * 3_600
        case .workday, .nightOfSleep: 8 * 3_600
        case .flightFrankfurtNewYork: 8 * 3_600 + 30 * 60
        case .weekend: 48 * 3_600
        }
    }

    /// Sizes for the total time (I2).
    public static let forTotal: [ConversionUnit] = [
        .issOrbit, .footballMatch, .movie, .marathonWorldRecord, .trainHamburgMunich, .flightFrankfurtNewYork,
        .workday, .nightOfSleep, .weekend,
    ]
    /// Sizes for the time saved by speed (I20).
    public static let forSaved: [ConversionUnit] = [.nap, .pastaCooking, .washingCycle]
}

/// "So long, the ISS needed to orbit the earth 25 times." `count` is 2…99.
public struct Conversion: Hashable, Sendable {
    public var unit: ConversionUnit
    public var count: Int

    public init(unit: ConversionUnit, count: Int) {
        self.unit = unit
        self.count = count
    }
}

/// I4. `daysInPeriod` counts only days up to now in the current period.
public struct ListeningDays: Hashable, Sendable {
    public var days: Int
    public var daysInPeriod: Int
    public var averagePerDay: TimeInterval

    public init(days: Int, daysInPeriod: Int, averagePerDay: TimeInterval) {
        self.days = days
        self.daysInPeriod = daysInPeriod
        self.averagePerDay = averagePerDay
    }
}

/// I5: ≤ 3 podcasts "you know what you want", 4–9 balanced, ≥ 10 "open to new things".
public enum VarietyTone: String, Hashable, Sendable {
    case focused, balanced, explorer
}

/// I6, share 0…1 of the period's listening.
public struct PodcastShare: Hashable, Sendable {
    public var podcast: PodcastRef
    public var seconds: TimeInterval
    public var share: Double

    public init(podcast: PodcastRef, seconds: TimeInterval, share: Double) {
        self.podcast = podcast
        self.seconds = seconds
        self.share = share
    }
}

/// I7. `playlist == nil` is "Ohne Playlist". Shares add up to 1.
public struct PlaylistShare: Hashable, Sendable {
    public var playlist: PlaylistID?
    public var seconds: TimeInterval
    public var share: Double

    public init(playlist: PlaylistID?, seconds: TimeInterval, share: Double) {
        self.playlist = playlist
        self.seconds = seconds
        self.share = share
    }
}

/// I9: the longest listening in one go.
public struct Marathon: Hashable, Sendable {
    public var seconds: TimeInterval
    public var start: Date
    public var podcast: PodcastRef

    public init(seconds: TimeInterval, start: Date, podcast: PodcastRef) {
        self.seconds = seconds
        self.start = start
        self.podcast = podcast
    }
}

/// I10: heard in `count` of `outOf` weeks (month) or months (year).
public struct Faithful: Hashable, Sendable {
    public var podcast: PodcastRef
    public var count: Int
    public var outOf: Int

    public init(podcast: PodcastRef, count: Int, outOf: Int) {
        self.podcast = podcast
        self.count = count
        self.outOf = outOf
    }
}

/// I11: most episodes of one podcast on one day.
public struct Binge: Hashable, Sendable {
    public var podcast: PodcastRef
    public var episodes: Int
    public var day: Date

    public init(podcast: PodcastRef, episodes: Int, day: Date) {
        self.podcast = podcast
        self.episodes = episodes
        self.day = day
    }
}

/// I12: subscribed in the period, `rank` among all podcasts of the period (1 = top).
public struct NewDiscovery: Hashable, Sendable {
    public var podcast: PodcastRef
    public var subscribedAt: Date
    public var rank: Int
    public var seconds: TimeInterval

    public init(podcast: PodcastRef, subscribedAt: Date, rank: Int, seconds: TimeInterval) {
        self.podcast = podcast
        self.subscribedAt = subscribedAt
        self.rank = rank
        self.seconds = seconds
    }
}

/// I13. `topPlaylist` is the playlist with most of that day (nil = "Ohne Playlist").
public struct RecordDay: Hashable, Sendable {
    public var day: Date
    public var seconds: TimeInterval
    public var topPodcast: PodcastRef
    public var topPlaylist: PlaylistID?

    public init(day: Date, seconds: TimeInterval, topPodcast: PodcastRef, topPlaylist: PlaylistID?) {
        self.day = day
        self.seconds = seconds
        self.topPodcast = topPodcast
        self.topPlaylist = topPlaylist
    }
}

/// I14. `current` is set only in the period containing now, when the streak reaches
/// today or yesterday.
public struct Streak: Hashable, Sendable {
    public var longest: Int
    public var longestStart: Date
    public var current: Int?

    public init(longest: Int, longestStart: Date, current: Int?) {
        self.longest = longest
        self.longestStart = longestStart
        self.current = current
    }
}

/// I16: the strongest week (month view) or month (year view), `start` its first day.
public struct StrongestStretch: Hashable, Sendable {
    public var start: Date
    public var seconds: TimeInterval

    public init(start: Date, seconds: TimeInterval) {
        self.start = start
        self.seconds = seconds
    }
}

/// Parts of the day (local time): morning 5–11, midday 11–14, afternoon 14–18,
/// evening 18–22, night 22–5.
public enum DayPart: String, Hashable, Sendable, CaseIterable {
    case morning, midday, afternoon, evening, night
}

/// I17. `seconds[weekday - 1][hour]`, weekday as in `Calendar` (1 = Sunday), hour 0…23.
public struct Heatmap: Hashable, Sendable {
    public var seconds: [[TimeInterval]]
    public var peakIsWeekend: Bool
    public var peakPart: DayPart

    public init(seconds: [[TimeInterval]], peakIsWeekend: Bool, peakPart: DayPart) {
        self.seconds = seconds
        self.peakIsWeekend = peakIsWeekend
        self.peakPart = peakPart
    }
}

/// I18, rules in plan §6.1.
public enum ListenerType: String, Hashable, Sendable, CaseIterable {
    case commuter, nightOwl, earlyBird, weekender, lunchBreak, afterWork, allRounder
}

public enum ListenerSpice: String, Hashable, Sendable, CaseIterable {
    /// Ø speed ≥ 1.5×.
    case fast
    /// Marathon ≥ 2 h.
    case stamina
    /// ≥ 20 % of sessions ended by the sleep timer.
    case sleeper
}

/// `share` is the share of listening that made the rule match (for `allRounder`: the
/// largest part of the day).
public struct ListenerProfile: Hashable, Sendable {
    public var type: ListenerType
    public var spice: ListenerSpice?
    public var share: Double

    public init(type: ListenerType, spice: ListenerSpice?, share: Double) {
        self.type = type
        self.spice = spice
        self.share = share
    }
}

/// I20. `average` = content ÷ listened time.
public struct Speed: Hashable, Sendable {
    public var average: Double
    public var savedSeconds: TimeInterval
    public var conversion: Conversion?

    public init(average: Double, savedSeconds: TimeInterval, conversion: Conversion?) {
        self.average = average
        self.savedSeconds = savedSeconds
        self.conversion = conversion
    }
}

/// I22. `lingering` is the started episode lying around the longest (current period only).
public struct Completion: Hashable, Sendable {
    public var rate: Double
    public var lingering: Lingering?

    public init(rate: Double, lingering: Lingering?) {
        self.rate = rate
        self.lingering = lingering
    }
}

public struct Lingering: Hashable, Sendable {
    public var episode: EpisodeID
    public var title: String
    public var podcastTitle: String
    public var position: TimeInterval
    /// Its first listening session.
    public var since: Date

    public init(episode: EpisodeID, title: String, podcastTitle: String, position: TimeInterval, since: Date) {
        self.episode = episode
        self.title = title
        self.podcastTitle = podcastTitle
        self.position = position
        self.since = since
    }
}

/// I23: sessions the sleep timer ended, and the podcast it ended most.
public struct Sleep: Hashable, Sendable {
    public var count: Int
    public var podcast: PodcastRef
    public var podcastCount: Int

    public init(count: Int, podcast: PodcastRef, podcastCount: Int) {
        self.count = count
        self.podcast = podcast
        self.podcastCount = podcastCount
    }
}

/// I24: median time from publishing to first listening, per playlist (nil = "Ohne Playlist").
public struct PlaylistFreshness: Hashable, Sendable {
    public var playlist: PlaylistID?
    public var median: TimeInterval

    public init(playlist: PlaylistID?, median: TimeInterval) {
        self.playlist = playlist
        self.median = median
    }
}

/// I44: Christmas Eve, New Year's Eve, New Year's Day of the year.
public enum Holiday: String, Hashable, Sendable, CaseIterable {
    case christmasEve, newYearsEve, newYearsDay
}

public struct HolidayListen: Hashable, Sendable {
    public var holiday: Holiday
    /// The latest moment listened that day.
    public var moment: EpisodeMoment

    public init(holiday: Holiday, moment: EpisodeMoment) {
        self.holiday = holiday
        self.moment = moment
    }
}

/// I26: subscribed before the period, new episodes in it, not a minute heard.
public struct NeglectedPodcast: Hashable, Sendable {
    public var podcast: PodcastRef
    public var newEpisodes: Int

    public init(podcast: PodcastRef, newEpisodes: Int) {
        self.podcast = podcast
        self.newEpisodes = newEpisodes
    }
}

/// I27: days to catch up at the current pace, and "without sleep".
public struct Backlog: Hashable, Sendable {
    public var seconds: TimeInterval
    public var days: Int
    public var nonstopDays: Int

    public init(seconds: TimeInterval, days: Int, nonstopDays: Int) {
        self.seconds = seconds
        self.days = days
        self.nonstopDays = nonstopDays
    }
}

/// I29: a bar per day (month view) or month (year view); `start` is its first moment.
public struct TrendBar: Hashable, Sendable {
    public var start: Date
    public var seconds: TimeInterval

    public init(start: Date, seconds: TimeInterval) {
        self.start = start
        self.seconds = seconds
    }
}

public struct Trend: Hashable, Sendable {
    public var bars: [TrendBar]
    /// Average over the bars up to now.
    public var average: TimeInterval

    public init(bars: [TrendBar], average: TimeInterval) {
        self.bars = bars
        self.average = average
    }
}

/// A value for one month (first day of the month).
public struct MonthValue: Hashable, Sendable {
    public var month: Date
    public var value: Double

    public init(month: Date, value: Double) {
        self.month = month
        self.value = value
    }
}

/// I30/I31: a podcast's share went from `fromShare` to `toShare` (0…1); ranks among the
/// podcasts of each side (`toRank == nil`: not heard any more). `monthly` is its share per
/// month for the line chart.
public struct ShareChange: Hashable, Sendable {
    public var podcast: PodcastRef
    public var fromShare: Double
    public var toShare: Double
    public var fromRank: Int
    public var toRank: Int?
    public var monthly: [MonthValue]

    public init(podcast: PodcastRef, fromShare: Double, toShare: Double, fromRank: Int, toRank: Int?, monthly: [MonthValue]) {
        self.podcast = podcast
        self.fromShare = fromShare
        self.toShare = toShare
        self.fromRank = fromRank
        self.toRank = toRank
        self.monthly = monthly
    }
}

/// I32: shares per month and playlist; `highlight` is the playlist whose share grew the
/// most and by which factor (≥ 2 to be named).
public struct PlaylistShift: Hashable, Sendable {
    public var months: [PlaylistMonth]
    public var highlight: PlaylistGrowth?

    public init(months: [PlaylistMonth], highlight: PlaylistGrowth?) {
        self.months = months
        self.highlight = highlight
    }
}

public struct PlaylistMonth: Hashable, Sendable {
    public var month: Date
    public var shares: [PlaylistShare]

    public init(month: Date, shares: [PlaylistShare]) {
        self.month = month
        self.shares = shares
    }
}

public struct PlaylistGrowth: Hashable, Sendable {
    public var playlist: PlaylistID?
    public var since: Date
    public var factor: Double

    public init(playlist: PlaylistID?, since: Date, factor: Double) {
        self.playlist = playlist
        self.since = since
        self.factor = factor
    }
}

/// I33: Ø speed per month with data; `from`/`to` are the first and last month.
public struct SpeedTrend: Hashable, Sendable {
    public var monthly: [MonthValue]

    public init(monthly: [MonthValue]) {
        self.monthly = monthly
    }

    public var from: MonthValue { monthly.first! }
    public var to: MonthValue { monthly.last! }
}

/// I35: each month with data and its top podcast.
public struct MonthTop: Hashable, Sendable {
    public var month: Date
    public var podcast: PodcastRef

    public init(month: Date, podcast: PodcastRef) {
        self.month = month
        self.podcast = podcast
    }
}
