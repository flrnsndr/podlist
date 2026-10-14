import Foundation

/// A subscribed podcast as the refresh order sees it.
public struct RefreshCandidate: Hashable, Sendable {
    public var podcast: PodcastID
    /// The last refresh attempt, failed ones included.
    public var lastRefreshedAt: Date?
    /// Notifications on or assigned to a playlist: its new episodes should arrive soon.
    public var isWatched: Bool

    public init(podcast: PodcastID, lastRefreshedAt: Date?, isWatched: Bool) {
        self.podcast = podcast
        self.lastRefreshedAt = lastRefreshedAt
        self.isWatched = isWatched
    }
}

/// When and in which order feeds refresh (A44, A63).
public enum RefreshSchedule {
    /// The earliest start of the next background refresh; when it really runs, iOS decides.
    public static let backgroundInterval: TimeInterval = 15 * 60
    /// iOS gives a background refresh about 30 s; after this no feed starts and running loads
    /// stop, so that saving and notifying still fit.
    public static let backgroundBudget: Duration = .seconds(20)
    /// Returning to the app refreshes once the last complete refresh is this old.
    public static let foregroundInterval: TimeInterval = 15 * 60

    /// Watched podcasts first, then the others; within each, the longest unrefreshed first,
    /// so a run cut short goes on there next time.
    public static func order(_ candidates: [RefreshCandidate]) -> [PodcastID] {
        candidates.enumerated().sorted { a, b in
            if a.element.isWatched != b.element.isWatched { return a.element.isWatched }
            let (dateA, dateB) = (a.element.lastRefreshedAt ?? .distantPast, b.element.lastRefreshedAt ?? .distantPast)
            return dateA != dateB ? dateA < dateB : a.offset < b.offset
        }.map(\.element.podcast)
    }

    /// Whether returning to the app refreshes; `nil`: no complete refresh in this app run.
    public static func isDue(lastCompleteRefresh: Date?, now: Date) -> Bool {
        guard let lastCompleteRefresh else { return true }
        return now.timeIntervalSince(lastCompleteRefresh) >= foregroundInterval
    }
}
