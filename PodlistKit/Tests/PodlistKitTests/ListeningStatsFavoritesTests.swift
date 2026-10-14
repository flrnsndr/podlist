import Foundation
import Testing
@testable import PodlistKit

// B. Favorites (I6–I12) and C. Records (I13–I16).
struct ListeningStatsFavoritesTests {
    private let a = StatsShow("A")
    private let b = StatsShow("B")
    private let c = StatsShow("C")

    // MARK: I6

    @Test func topFiveWithSharesNeedsTwoPodcasts() {
        let shows = (0 ..< 7).map { StatsShow("S\($0)") }
        var sessions: [ListeningRecord] = []
        for (index, show) in shows.enumerated() {
            sessions.append(statsRec(statsAt(2026, 9, 5, 6 + index), minutes: Double(100 - index * 10), show))
        }
        let top = statsReport(statsSep, sessions).topPodcasts
        #expect(top?.count == 5)
        #expect(top?.map(\.podcast.id) == shows.prefix(5).map(\.id))
        #expect(near(top?.first?.share, 100.0 / 490))
        #expect(statsReport(statsSep, [statsRec(statsAt(2026, 9, 5), minutes: 30, a)]).topPodcasts == nil)
    }

    @Test func tiesAreBrokenByWhoWasHeardFirstThenByTitle() {
        let sessions = [statsRec(statsAt(2026, 9, 6, 9), minutes: 30, b), statsRec(statsAt(2026, 9, 5, 9), minutes: 30, a)]
        #expect(statsReport(statsSep, sessions).topPodcasts?.map(\.podcast.title) == ["A", "B"])
        let same = [statsRec(statsAt(2026, 9, 5, 9), minutes: 30, b), statsRec(statsAt(2026, 9, 5, 9), minutes: 30, a)]
        #expect(statsReport(statsSep, same).topPodcasts?.map(\.podcast.title) == ["A", "B"])
    }

    @Test func aPodcastIsTitledByItsMostRecentSession() {
        let old = StatsShow("Old name")
        let renamed = ListeningRecord(
            startedAt: statsAt(2026, 9, 10, 9), endedAt: statsAt(2026, 9, 10, 9, 30), listenedSeconds: 1_800,
            episode: EpisodeID(), podcast: old.id, podcastTitle: "New name")
        let sessions = [statsRec(statsAt(2026, 9, 5, 9), minutes: 30, old), renamed, statsRec(statsAt(2026, 9, 6, 9), minutes: 5, a)]
        #expect(statsReport(statsSep, sessions).topPodcasts?.first?.podcast.title == "New name")
    }

    @Test func sessionsWithoutAPodcastGroupByTitle() {
        func orphan(_ title: String, _ day: Int) -> ListeningRecord {
            ListeningRecord(
                startedAt: statsAt(2026, 9, day, 9), endedAt: statsAt(2026, 9, day, 9, 30), listenedSeconds: 1_800,
                episode: EpisodeID(), podcast: nil, podcastTitle: title)
        }
        let top = statsReport(statsSep, [orphan("Gone", 5), orphan("Gone", 6), orphan("Other", 7)]).topPodcasts
        #expect(top?.map(\.podcast.title) == ["Gone", "Other"])
        #expect(top?.first?.podcast.id == nil)
    }

    // MARK: I7

    @Test func playlistAttributionBlockSingleEpisodeWithZeroOneAndTwoPlaylists() {
        let (p1, p2, p3, p4) = (PlaylistID(), PlaylistID(), PlaylistID(), PlaylistID())
        let two = StatsShow("Two"), none = StatsShow("None"), block = StatsShow("Block"), one = StatsShow("One")
        let library = StatsLibrary(
            podcasts: [two.podcast(playlists: [p1, p2]), block.podcast(playlists: [p1]), one.podcast(playlists: [p4])],
            playlists: [
                StatsPlaylist(id: p1, name: "P1"), StatsPlaylist(id: p2, name: "P2"), StatsPlaylist(id: p3, name: "P3"),
                StatsPlaylist(id: p4, name: "P4"),
            ])
        let sessions = [
            statsRec(statsAt(2026, 9, 5, 8), minutes: 60, two),
            statsRec(statsAt(2026, 9, 5, 10), minutes: 60, none),
            // The block wins over the podcast's own playlists.
            statsRec(statsAt(2026, 9, 5, 12), minutes: 60, block, playlist: p3),
            statsRec(statsAt(2026, 9, 5, 14), minutes: 30, one),
        ]
        let shares = statsReport(statsSep, sessions, library: library).playlists
        let seconds = Dictionary(uniqueKeysWithValues: (shares ?? []).map { ($0.playlist, $0.seconds) })
        #expect(near(seconds[p1], 1_800) && near(seconds[p2], 1_800) && near(seconds[p3], 3_600))
        #expect(near(seconds[p4], 1_800) && near(seconds[nil], 3_600) && seconds.count == 5)
        #expect(near(shares?.reduce(0) { $0 + $1.share }, 1))
        // Most first; "Ohne Playlist" after an equal playlist; then by name.
        #expect(shares?.map(\.playlist) == [p3, nil, p1, p2, p4])
    }

    @Test func withoutPlaylistIsNeverTheFavorite() {
        let p1 = PlaylistID()
        let sessions = [statsRec(statsAt(2026, 9, 5, 8), minutes: 90, a), statsRec(statsAt(2026, 9, 5, 10), minutes: 30, b, playlist: p1)]
        let report = statsReport(statsSep, sessions)
        #expect(report.playlists?.first?.playlist == nil)
        #expect(report.favoritePlaylist?.playlist == p1)
    }

    @Test func aPlaylistThatIsGoneStillCounts() {
        let gone = PlaylistID()
        let sessions = [statsRec(statsAt(2026, 9, 5, 8), minutes: 60, a, playlist: gone), statsRec(statsAt(2026, 9, 5, 10), minutes: 30, b)]
        #expect(statsReport(statsSep, sessions).playlists?.first?.playlist == gone)
    }

    @Test func oneEntryIsNoDistribution() {
        let sessions = [statsRec(statsAt(2026, 9, 5, 8), minutes: 60, a), statsRec(statsAt(2026, 9, 6, 8), minutes: 60, b)]
        #expect(statsReport(statsSep, sessions).playlists == nil)
    }

    // MARK: I8

    @Test(arguments: [(other: 49.0, expected: false), (other: 50.0, expected: true)])
    func genreNeedsThreeHours(other: Double, expected: Bool) {
        let library = StatsLibrary(podcasts: [
            a.podcast(categories: ["History", "Society"]), b.podcast(categories: ["Science"]), c.podcast(),
        ])
        let sessions = [
            statsRec(statsAt(2026, 9, 5, 8), minutes: 100, a), statsRec(statsAt(2026, 9, 6, 8), minutes: other, b),
            statsRec(statsAt(2026, 9, 7, 8), minutes: 30, c),
        ]
        let genre = statsReport(statsSep, sessions, library: library).genre
        #expect((genre != nil) == expected)
        if expected {
            #expect(genre?.name == "History")
            // Podcasts without a genre are left out of the share.
            #expect(near(genre?.share, 100.0 / 150))
        }
    }

    @Test func noGenreNoInsight() {
        let sessions = [statsRec(statsAt(2026, 9, 5, 8), minutes: 300, a)]
        #expect(statsReport(statsSep, sessions, library: StatsLibrary(podcasts: [a.podcast()])).genre == nil)
        #expect(statsReport(statsSep, sessions).genre == nil)
    }

    // MARK: I9

    @Test(arguments: [(gap: 299.0, merged: true), (gap: 300.0, merged: false)])
    func sessionsOfOneEpisodeMergeBelowFiveMinutes(gap: Double, merged: Bool) {
        let episode = EpisodeID()
        let first = statsRec(statsAt(2026, 9, 5, 8), minutes: 20, a, episode: episode)
        let second = statsRec(statsAt(2026, 9, 5, 8, 20, 0).addingTimeInterval(gap), minutes: 30, a, episode: episode)
        let marathon = statsReport(statsSep, [first, second]).marathon
        #expect((marathon != nil) == merged)
        if merged {
            #expect(near(marathon?.seconds, 3_000) && marathon?.start == statsAt(2026, 9, 5, 8))
        }
    }

    @Test(arguments: [(seconds: 2_699.0, expected: false), (seconds: 2_700.0, expected: true)])
    func marathonNeedsFortyFiveMinutes(seconds: Double, expected: Bool) {
        let marathon = statsReport(statsSep, [statsRec(statsAt(2026, 9, 5, 8), minutes: seconds / 60, a)]).marathon
        #expect((marathon != nil) == expected)
    }

    @Test func differentEpisodesNeverMerge() {
        let sessions = [
            statsRec(statsAt(2026, 9, 5, 8), minutes: 30, a), statsRec(statsAt(2026, 9, 5, 8, 30), minutes: 30, a),
        ]
        #expect(statsReport(statsSep, sessions).marathon == nil)
    }

    // MARK: I10

    @Test(arguments: [(weeks: 2, expected: false), (weeks: 3, expected: true)])
    func faithfulCountsWeeksInAMonth(weeks: Int, expected: Bool) {
        // September 2026 touches five weeks (from 31 Aug, 7, 14, 21, 28 Sep).
        let days = [2, 9, 16].prefix(weeks)
        let sessions = days.map { statsRec(statsAt(2026, 9, $0, 8), minutes: 20, a) } + [statsRec(statsAt(2026, 9, 3, 9), minutes: 5, b)]
        let faithful = statsReport(statsSep, sessions).faithful
        #expect((faithful != nil) == expected)
        if expected { #expect(faithful?.podcast.title == "A" && faithful?.count == 3 && faithful?.outOf == 5) }
    }

    @Test func faithfulInTheCurrentMonthCountsWeeksUpToNow() {
        let sessions = [1, 6, 13].map { statsRec(statsAt(2026, 10, $0, 8), minutes: 20, a) }
        #expect(statsReport(statsOct, sessions).faithful?.outOf == 4)
    }

    @Test(arguments: [(months: 2, expected: false), (months: 3, expected: true)])
    func faithfulCountsMonthsInAYear(months: Int, expected: Bool) {
        let sessions = [1, 3, 5].prefix(months).map { statsRec(statsAt(2026, $0, 8, 8), minutes: 20, a) }
        let faithful = statsReport(statsYear, sessions).faithful
        #expect((faithful != nil) == expected)
        if expected { #expect(faithful?.count == 3 && faithful?.outOf == 10) }
    }

    // MARK: I11

    @Test(arguments: [(episodes: 2, expected: false), (episodes: 3, expected: true)])
    func bingeNeedsThreeEpisodesInADay(episodes: Int, expected: Bool) {
        let sessions = (0 ..< episodes).map { statsRec(statsAt(2026, 9, 6, 8 + $0), minutes: 20, a) }
        let binge = statsReport(statsSep, sessions).binge
        #expect((binge != nil) == expected)
        if expected { #expect(binge?.episodes == 3 && binge?.day == statsAt(2026, 9, 6, 0) && binge?.podcast.title == "A") }
    }

    @Test func oneEpisodeInThreeSessionsIsNoBinge() {
        let episode = EpisodeID()
        let sessions = (0 ..< 3).map { statsRec(statsAt(2026, 9, 6, 8 + $0), minutes: 20, a, episode: episode) }
        #expect(statsReport(statsSep, sessions).binge == nil)
    }

    // MARK: I12

    @Test func newDiscoveryIsSubscribedInThePeriodWithAnHour() {
        let library = StatsLibrary(podcasts: [
            a.podcast(subscribedAt: statsAt(2026, 9, 3)), b.podcast(subscribedAt: statsAt(2026, 8, 3)),
            c.podcast(subscribedAt: statsAt(2026, 9, 20)),
        ])
        let sessions = [
            statsRec(statsAt(2026, 9, 10, 8), minutes: 61, a), statsRec(statsAt(2026, 9, 11, 8), minutes: 120, b),
            statsRec(statsAt(2026, 9, 21, 8), minutes: 59, c), statsRec(statsAt(2026, 9, 1, 8), minutes: 5, b),
        ]
        let discovery = statsReport(statsSep, sessions, library: library).newDiscovery
        #expect(discovery?.podcast.title == "A" && discovery?.rank == 2 && discovery?.subscribedAt == statsAt(2026, 9, 3))
        // Only C under an hour, or only an old subscription: nothing.
        #expect(statsReport(statsSep, [sessions[1], sessions[2], sessions[3]], library: library).newDiscovery == nil)
    }

    @Test func subscriptionsFromBeforeTheRecordingAreNoDiscovery() {
        // All subscribed by an OPML import on 3 September, recording from 10 September.
        let library = StatsLibrary(podcasts: [a.podcast(subscribedAt: statsAt(2026, 9, 3))])
        let sessions = [statsRec(statsAt(2026, 9, 10, 8), minutes: 120, a), statsRec(statsAt(2026, 9, 11, 8), minutes: 30, b)]
        #expect(statsReport(statsSep, sessions, library: library).newDiscovery == nil)
    }

    // MARK: I13

    @Test func recordDayNeedsTwoDaysAndNamesWhatPlayed() {
        let (p1, p2) = (PlaylistID(), PlaylistID())
        let sessions = [
            statsRec(statsAt(2026, 9, 5, 8), minutes: 30, a, playlist: p1),
            statsRec(statsAt(2026, 9, 12, 8), minutes: 60, a, playlist: p1),
            statsRec(statsAt(2026, 9, 12, 10), minutes: 90, b, playlist: p2),
        ]
        let record = statsReport(statsSep, sessions).recordDay
        #expect(record?.day == statsAt(2026, 9, 12, 0) && near(record?.seconds, 9_000))
        #expect(record?.topPodcast.title == "B" && record?.topPlaylist == p2)
        #expect(statsReport(statsSep, Array(sessions.dropFirst())).recordDay == nil)
    }

    // MARK: I14

    @Test func streakCountsAcrossTheMonthBoundaryForTheCurrentRun() {
        let days = [(9, 29), (9, 30), (10, 1), (10, 2), (10, 3)]
        let sessions = days.map { statsRec(statsAt(2026, $0.0, $0.1, 8), minutes: 30, a) }
        let streak = statsReport(statsOct, sessions, now: statsAt(2026, 10, 3, 12)).streak
        // The current run reaches back into September, and the longest is never shorter.
        #expect(streak?.longest == 5 && streak?.longestStart == statsAt(2026, 9, 29, 0) && streak?.current == 5)
    }

    @Test func aCurrentRunFromTheLastMonthShowsOnItsSecondDay() {
        let days = [(9, 28), (9, 29), (9, 30), (10, 1), (10, 2)]
        let sessions = days.map { statsRec(statsAt(2026, $0.0, $0.1, 8), minutes: 30, a) }
        let streak = statsReport(statsOct, sessions, now: statsAt(2026, 10, 2, 12)).streak
        #expect(streak?.longest == 5 && streak?.current == 5)
    }

    @Test(arguments: [(now: 4, current: 3 as Int?), (now: 5, current: nil as Int?)])
    func currentStreakReachesTodayOrYesterday(now: Int, current: Int?) {
        let sessions = (1 ... 3).map { statsRec(statsAt(2026, 10, $0, 8), minutes: 30, a) }
        let streak = statsReport(statsOct, sessions, now: statsAt(2026, 10, now, 12)).streak
        #expect(streak?.longest == 3)
        #expect(streak?.current == current)
    }

    @Test func aPastPeriodHasNoCurrentStreak() {
        let sessions = (28 ... 30).map { statsRec(statsAt(2026, 9, $0, 8), minutes: 30, a) }
        let streak = statsReport(statsSep, sessions).streak
        #expect(streak?.longest == 3 && streak?.current == nil)
    }

    @Test func streakNeedsThreeDaysAndAGapBreaksIt() {
        let two = [1, 2].map { statsRec(statsAt(2026, 9, $0, 8), minutes: 30, a) }
        #expect(statsReport(statsSep, two).streak == nil)
        let gap = [1, 2, 4, 5, 6].map { statsRec(statsAt(2026, 9, $0, 8), minutes: 30, a) }
        let streak = statsReport(statsSep, gap).streak
        #expect(streak?.longest == 3 && streak?.longestStart == statsAt(2026, 9, 4, 0))
    }

    // MARK: I15

    @Test(arguments: [(second: 9, expected: false), (second: 10, expected: true)])
    func longestBreakNeedsSevenDays(second: Int, expected: Bool) {
        let sessions = [statsRec(statsAt(2026, 1, 2, 8), minutes: 30, a), statsRec(statsAt(2026, 1, second, 8), minutes: 30, a)]
        let result = statsReport(statsYear, sessions, now: statsAt(2027, 2, 1)).longestBreak
        #expect((result != nil) == expected)
        if expected { #expect(result?.days == 7 && result?.start == statsAt(2026, 1, 3, 0)) }
    }

    @Test func longestBreakInTheCurrentYearIncludesTheSilenceUpToToday() {
        let sessions = [statsRec(statsAt(2026, 10, 10, 8), minutes: 30, a), statsRec(statsAt(2026, 10, 12, 8), minutes: 30, a)]
        let result = statsReport(statsYear, sessions).longestBreak
        #expect(result?.days == 7 && result?.start == statsAt(2026, 10, 13, 0))
    }

    @Test func longestBreakIsYearOnly() {
        let sessions = [statsRec(statsAt(2026, 9, 1, 8), minutes: 30, a), statsRec(statsAt(2026, 9, 25, 8), minutes: 30, a)]
        #expect(statsReport(statsSep, sessions).longestBreak == nil)
    }

    // MARK: I16

    @Test func strongestWeekIsClippedToTheMonth() {
        let sessions = [statsRec(statsAt(2026, 9, 1, 8), minutes: 60, a), statsRec(statsAt(2026, 9, 15, 8), minutes: 30, a)]
        let stretch = statsReport(statsSep, sessions).strongestStretch
        #expect(stretch?.start == statsAt(2026, 9, 1, 0) && near(stretch?.seconds, 3_600))
        #expect(statsReport(statsSep, [sessions[0]]).strongestStretch == nil)
    }

    @Test func strongestMonthOfTheYear() {
        let sessions = [statsRec(statsAt(2026, 3, 5, 8), minutes: 300, a), statsRec(statsAt(2026, 6, 5, 8), minutes: 120, a)]
        let stretch = statsReport(statsYear, sessions).strongestStretch
        #expect(stretch?.start == statsAt(2026, 3, 1, 0) && near(stretch?.seconds, 18_000))
        #expect(statsReport(statsYear, [sessions[0]]).strongestStretch == nil)
    }
}
