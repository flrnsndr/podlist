import Foundation
import Testing
@testable import PodlistKit

private let sport = PlaylistID()
private let news = PlaylistID()
private let kids = PlaylistID()
private let lage = PodcastID()
private let kicker = PodcastID()
private let sandmann = PodcastID()

// Listening history (concept §4.12, N81–N86, A70–A76): one row per started episode, on the
// day it last played, newest first, from the listening log.
struct ListeningHistoryTests {
    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()

    /// 2026-10-12 at `hour`:`minute` (Berlin), `days` later.
    private static func date(days: Int = 0, _ hour: Int, _ minute: Int = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: hour, minute: minute))!
        return calendar.date(byAdding: .day, value: days, to: base)!
    }

    private static func day(_ days: Int) -> Date { calendar.startOfDay(for: date(days: days, 12)) }

    private static func session(
        _ episode: EpisodeID, _ podcast: PodcastID? = lage, at start: Date, minutes: Double = 10,
        from: TimeInterval = 0, to: TimeInterval? = nil, playlist: PlaylistID? = nil,
        title: String = "Snapshot", podcastTitle: String = "Podcast", duration: TimeInterval? = 3600
    ) -> ListeningRecord {
        ListeningRecord(
            startedAt: start, endedAt: start.addingTimeInterval(minutes * 60), listenedSeconds: minutes * 60,
            startPosition: from, endPosition: to ?? from + minutes * 60, episode: episode, podcast: podcast,
            playlist: playlist, episodeTitle: title, podcastTitle: podcastTitle, episodeDuration: duration)
    }

    private static func state(
        _ title: String, podcastTitle: String = "Lage der Nation", subtitle: String? = nil,
        duration: TimeInterval? = 3600, position: TimeInterval = 0, isPlayed: Bool = false
    ) -> HistoryEpisodeState {
        HistoryEpisodeState(
            title: title, podcastTitle: podcastTitle, subtitle: subtitle, duration: duration,
            playbackPosition: position, isPlayed: isPlayed)
    }

    private static func entries(
        _ sessions: [ListeningRecord], episodes: [EpisodeID: HistoryEpisodeState],
        podcasts: [PodcastID: Set<PlaylistID>] = [:], hidden: Set<PlaylistID> = [],
        tags: Set<PlaylistID> = [sport, news, kids]
    ) -> [HistoryEntry] {
        ListeningHistory.entries(
            sessions: sessions, episodes: episodes, podcastPlaylists: podcasts, hidden: hidden, tags: tags,
            calendar: calendar)
    }

    // MARK: Rows and days

    /// N82: one row per episode, on the day it last played; no count of sessions.
    @Test func anEpisodeHeardOnTwoDaysIsOneRowOnTheLaterDay() {
        let a = EpisodeID(), b = EpisodeID()
        let sessions = [
            Self.session(a, at: Self.date(days: -2, 8)),
            Self.session(b, at: Self.date(days: -1, 9)),
            Self.session(a, at: Self.date(days: 0, 7), from: 600),
        ]
        let all = Self.entries(sessions, episodes: [a: Self.state("A"), b: Self.state("B")])
        let days = ListeningHistory.days(all, sessions: sessions, query: HistoryQuery(), calendar: Self.calendar)
        #expect(days.map(\.id) == [Self.day(0), Self.day(-1)])
        #expect(days.map { $0.entries.map(\.id) } == [[a], [b]])
    }

    @Test func rowsOfADayAreNewestFirstByTheEndOfTheirLastSession() {
        let a = EpisodeID(), b = EpisodeID(), c = EpisodeID()
        let sessions = [
            Self.session(a, at: Self.date(7), minutes: 120),
            Self.session(b, at: Self.date(8)),
            Self.session(c, at: Self.date(18)),
        ]
        let all = Self.entries(sessions, episodes: [a: Self.state("A"), b: Self.state("B"), c: Self.state("C")])
        let days = ListeningHistory.days(all, sessions: sessions, query: HistoryQuery(), calendar: Self.calendar)
        #expect(days.first?.entries.map(\.id) == [c, a, b])
    }

    /// A70: a session belongs to the day it began, also past midnight.
    @Test func aSessionPastMidnightBelongsToTheDayItBegan() {
        let a = EpisodeID()
        let sessions = [Self.session(a, at: Self.date(days: -1, 23, 50), minutes: 30)]
        let all = Self.entries(sessions, episodes: [a: Self.state("A")])
        let days = ListeningHistory.days(all, sessions: sessions, query: HistoryQuery(), calendar: Self.calendar)
        #expect(days.map(\.id) == [Self.day(-1)])
        #expect(days.first?.listenedSeconds == 1800)
    }

    /// A70: the day's time counts every session of that day of the episodes shown, also of an
    /// episode whose row moved on to a later day.
    @Test func theDaysListeningTimeCountsAllItsSessionsOfShownEpisodes() {
        let a = EpisodeID(), b = EpisodeID()
        let sessions = [
            Self.session(a, at: Self.date(days: -1, 8), minutes: 20),
            Self.session(b, at: Self.date(days: -1, 9), minutes: 15),
            Self.session(b, at: Self.date(days: -1, 18), minutes: 5),
            Self.session(a, at: Self.date(days: 0, 8), minutes: 10),
        ]
        let all = Self.entries(sessions, episodes: [a: Self.state("A"), b: Self.state("B")])
        let days = ListeningHistory.days(all, sessions: sessions, query: HistoryQuery(), calendar: Self.calendar)
        #expect(days.map(\.listenedSeconds) == [600, 2400])

        let onlyB = ListeningHistory.days(all, sessions: sessions, query: HistoryQuery(search: "B"), calendar: Self.calendar)
        #expect(onlyB.map(\.listenedSeconds) == [1200], "a filter also filters the day's time")
    }

    // MARK: What a row shows

    @Test func anAvailableEpisodeShowsItsCurrentTitlesAndState() throws {
        let a = EpisodeID()
        let sessions = [Self.session(a, at: Self.date(8), title: "Old title", podcastTitle: "Old podcast")]
        let entry = try #require(Self.entries(sessions, episodes: [
            a: Self.state("New title", podcastTitle: "New podcast", subtitle: "Kurz", duration: 4000, position: 120),
        ]).first)
        #expect(entry.title == "New title")
        #expect(entry.podcastTitle == "New podcast")
        #expect(entry.subtitle == "Kurz")
        #expect(entry.duration == 4000)
        #expect(entry.isAvailable)
        #expect(entry.lastActiveAt == Self.date(8, 10))
    }

    /// An episode deleted after unsubscribing keeps its snapshot titles, without actions.
    @Test func aDeletedEpisodeShowsItsSnapshot() throws {
        let a = EpisodeID()
        let sessions = [
            Self.session(a, at: Self.date(days: -1, 8), title: "Older", podcastTitle: "P1", duration: 1000),
            Self.session(a, at: Self.date(8), title: "Latest", podcastTitle: "P2", duration: 2000),
        ]
        let entry = try #require(Self.entries(sessions, episodes: [:]).first)
        #expect(!entry.isAvailable)
        #expect(entry.title == "Latest")
        #expect(entry.podcastTitle == "P2")
        #expect(entry.duration == 2000)
        #expect(!entry.isUnfinished)
    }

    /// A71: the bar joins what played in all sessions, start to end position, within the duration.
    @Test func heardPartsJoinAllSessions() throws {
        let a = EpisodeID()
        let sessions = [
            Self.session(a, at: Self.date(8), from: 0, to: 600),
            Self.session(a, at: Self.date(9), from: 600, to: 900),
            Self.session(a, at: Self.date(10), from: 2000, to: 2500),
            Self.session(a, at: Self.date(11), from: 2400, to: 2300),
            Self.session(a, at: Self.date(12), from: 3500, to: 9000),
            Self.session(a, at: Self.date(13), from: 100, to: 100),
        ]
        let entry = try #require(Self.entries(sessions, episodes: [a: Self.state("A", duration: 3600)]).first)
        #expect(entry.heard == [0...900, 2000...2500, 3500...3600])
        #expect(entry.heardFraction == (900 + 500 + 100) / 3600.0)
    }

    @Test func withoutADurationThereIsNoBar() throws {
        let a = EpisodeID()
        let sessions = [Self.session(a, at: Self.date(8), duration: nil)]
        let entry = try #require(Self.entries(sessions, episodes: [a: Self.state("A", duration: nil)]).first)
        #expect(entry.duration == nil)
        #expect(entry.heardFraction == nil)
    }

    /// A72: the pill is the playlist of the last session if it still is a tag; "Alles",
    /// deleted playlists and single episodes get none.
    @Test(arguments: [(sport, sport), (PlaylistID(), nil), (nil, nil)] as [(PlaylistID?, PlaylistID?)])
    func thePillIsTheLastSessionsPlaylist(last: PlaylistID?, expected: PlaylistID?) throws {
        let a = EpisodeID()
        let sessions = [
            Self.session(a, at: Self.date(8), playlist: news),
            Self.session(a, at: Self.date(9), playlist: last),
        ]
        let entry = try #require(Self.entries(sessions, episodes: [a: Self.state("A")]).first)
        #expect(entry.lastPlaylist == expected)
    }

    // MARK: Filters

    /// A73: "Nicht beendet" = a listening position and not played; deleted episodes never.
    @Test func unfinishedMeansStartedAndNotPlayed() {
        let started = EpisodeID(), played = EpisodeID(), reset = EpisodeID(), gone = EpisodeID()
        let sessions = [started, played, reset, gone].enumerated().map { Self.session($1, at: Self.date(8 + $0)) }
        let all = Self.entries(sessions, episodes: [
            started: Self.state("Started", position: 300),
            played: Self.state("Played", position: 0, isPlayed: true),
            reset: Self.state("Reset", position: 0),
        ])
        let days = ListeningHistory.days(all, sessions: sessions, query: HistoryQuery(onlyUnfinished: true), calendar: Self.calendar)
        #expect(days.flatMap(\.entries).map(\.id) == [started])
    }

    /// N84, N85: like the library. "Alle" leaves out podcasts whose playlists are all hidden;
    /// their chip shows them; "Ohne Playlist" are podcasts without playlists (or unknown ones).
    @Test(arguments: [
        (PlaylistFilter.all, ["Lage", "Kicker", "Unknown"]),
        (.playlist(sport), ["Kicker"]),
        (.playlist(kids), ["Lage", "Sandmann"]),
        (.withoutPlaylist, ["Unknown"]),
    ] as [(PlaylistFilter, [String])])
    func playlistFilterWorksLikeTheLibrary(filter: PlaylistFilter, expected: [String]) {
        let l = EpisodeID(), k = EpisodeID(), s = EpisodeID(), u = EpisodeID()
        let sessions = [
            Self.session(l, lage, at: Self.date(11)),
            Self.session(k, kicker, at: Self.date(10)),
            Self.session(s, sandmann, at: Self.date(9)),
            Self.session(u, nil, at: Self.date(8)),
        ]
        let all = Self.entries(
            sessions,
            episodes: [l: Self.state("Lage"), k: Self.state("Kicker"), s: Self.state("Sandmann"), u: Self.state("Unknown")],
            podcasts: [lage: [news, kids], kicker: [sport], sandmann: [kids]], hidden: [kids])
        let days = ListeningHistory.days(all, sessions: sessions, query: HistoryQuery(filter: filter), calendar: Self.calendar)
        #expect(days.flatMap(\.entries).map(\.title) == expected)
    }

    /// N83: title, podcast and short description; every word somewhere, any case and accents;
    /// never the show notes (they are not part of the input at all).
    @Test(arguments: [
        ("wahlrecht", ["Wahlrecht"]),
        ("LAGE wahl", ["Wahlrecht"]),
        ("Grundgesetz", ["Klimageld"]),
        ("fussball", ["Bundesliga"]),
        ("handball", []),
        ("fußball", ["Bundesliga"]),
        ("muller", ["Bundesliga"]),
        ("  ", ["Wahlrecht", "Klimageld", "Bundesliga"]),
    ] as [(String, [String])])
    func searchMatchesTitlePodcastAndSubtitle(search: String, expected: [String]) {
        let a = EpisodeID(), b = EpisodeID(), c = EpisodeID()
        let sessions = [
            Self.session(a, at: Self.date(10)),
            Self.session(b, at: Self.date(9)),
            Self.session(c, kicker, at: Self.date(8)),
        ]
        let all = Self.entries(sessions, episodes: [
            a: Self.state("Wahlrecht"),
            b: Self.state("Klimageld", subtitle: "Was das Grundgesetz dazu sagt"),
            c: Self.state("Bundesliga", podcastTitle: "Kicker Fußball", subtitle: "Mit Thomas Müller"),
        ])
        let days = ListeningHistory.days(all, sessions: sessions, query: HistoryQuery(search: search), calendar: Self.calendar)
        #expect(days.flatMap(\.entries).map(\.title) == expected)
    }

    @Test func aDeletedEpisodeIsFoundByItsSnapshotTitle() {
        let a = EpisodeID()
        let sessions = [Self.session(a, at: Self.date(8), title: "Alte Folge", podcastTitle: "Gekündigt")]
        let all = Self.entries(sessions, episodes: [:])
        let days = ListeningHistory.days(all, sessions: sessions, query: HistoryQuery(search: "gekündigt"), calendar: Self.calendar)
        #expect(days.flatMap(\.entries).map(\.id) == [a])
    }

    // MARK: A year ago

    /// A75: the episodes whose sessions began on the same day last year, last one first,
    /// also when their row moved on to a later day; the playlist filter applies.
    @Test func aYearAgoShowsTheEpisodesOfThatDay() {
        let yearAgo = Self.calendar.date(byAdding: .year, value: -1, to: Self.date(8))!
        let a = EpisodeID(), b = EpisodeID(), c = EpisodeID(), d = EpisodeID()
        let sessions = [
            Self.session(a, at: yearAgo),
            Self.session(b, kicker, at: yearAgo.addingTimeInterval(3600)),
            Self.session(c, at: yearAgo.addingTimeInterval(-86_400)),
            Self.session(a, at: Self.date(days: -3, 8)),
            Self.session(d, at: Self.date(9)),
        ]
        let all = Self.entries(
            sessions, episodes: [a: Self.state("A"), b: Self.state("B"), c: Self.state("C"), d: Self.state("D")],
            podcasts: [lage: [news], kicker: [sport]])
        let now = Self.date(20)
        #expect(ListeningHistory.yearAgo(all, sessions: sessions, filter: .all, now: now, calendar: Self.calendar).map(\.id) == [b, a])
        #expect(ListeningHistory.yearAgo(all, sessions: sessions, filter: .playlist(news), now: now, calendar: Self.calendar).map(\.id) == [a])
    }

    @Test func onTheTwentyNinthOfFebruaryAYearAgoIsTheTwentyEighth() {
        let leapDay = Self.calendar.date(from: DateComponents(year: 2028, month: 2, day: 29, hour: 20))!
        let a = EpisodeID()
        let sessions = [Self.session(a, at: Self.calendar.date(from: DateComponents(year: 2027, month: 2, day: 28, hour: 8))!)]
        let all = Self.entries(sessions, episodes: [a: Self.state("A")])
        #expect(ListeningHistory.yearAgo(all, sessions: sessions, filter: .all, now: leapDay, calendar: Self.calendar).map(\.id) == [a])
    }

    // MARK: Statistics

    /// A76: "Im Hörverlauf ›" from the statistics jumps to the latest day of its period.
    @Test func theLatestDayOfAPeriod() {
        let days = [0, -1, -20, -40].map { HistoryDay(id: Self.day($0), listenedSeconds: 0, entries: []) }
        let september = Self.calendar.dateInterval(of: .month, for: Self.date(days: -20, 12))!
        #expect(ListeningHistory.latestDay(in: september, of: days) == Self.day(-20))
        let august = Self.calendar.dateInterval(of: .month, for: Self.date(days: -70, 12))!
        #expect(ListeningHistory.latestDay(in: august, of: days) == nil)
    }
}
