import Foundation
import Testing
@testable import PodlistKit

/// In which order feeds refresh and when returning to the app refreshes (A44, A63).
struct RefreshScheduleTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)

    private func candidate(_ id: PodcastID, minutesAgo: Double?, watched: Bool = true) -> RefreshCandidate {
        RefreshCandidate(
            podcast: id, lastRefreshedAt: minutesAgo.map { Self.now.addingTimeInterval(-$0 * 60) }, isWatched: watched)
    }

    /// A44: the longest unrefreshed first, never refreshed before all others.
    @Test func longestUnrefreshedFirst() {
        let (a, b, c) = (PodcastID(), PodcastID(), PodcastID())
        let order = RefreshSchedule.order([candidate(a, minutesAgo: 5), candidate(b, minutesAgo: 60), candidate(c, minutesAgo: nil)])
        #expect(order == [c, b, a])
    }

    /// A44: podcasts with notifications or a playlist come first, however recently they were refreshed.
    @Test func watchedPodcastsFirst() {
        let (watched, unwatched, never) = (PodcastID(), PodcastID(), PodcastID())
        let order = RefreshSchedule.order([
            candidate(unwatched, minutesAgo: 600, watched: false),
            candidate(never, minutesAgo: nil, watched: false),
            candidate(watched, minutesAgo: 1),
        ])
        #expect(order == [watched, never, unwatched])
    }

    /// Equal dates keep the input order, so the order is deterministic.
    @Test func equalDatesKeepTheInputOrder() {
        let ids = (0..<5).map { _ in PodcastID() }
        #expect(RefreshSchedule.order(ids.map { candidate($0, minutesAgo: 10) }) == ids)
    }

    /// A63
    @Test(arguments: [(nil, true), (0.0, false), (14.9, false), (15.0, true), (60.0, true), (-5.0, false)] as [(Double?, Bool)])
    func returningRefreshesAfterFifteenMinutes(minutesAgo: Double?, isDue: Bool) {
        let last = minutesAgo.map { Self.now.addingTimeInterval(-$0 * 60) }
        #expect(RefreshSchedule.isDue(lastCompleteRefresh: last, now: Self.now) == isDue)
    }
}
