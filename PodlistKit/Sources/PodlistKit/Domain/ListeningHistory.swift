import Foundation

/// What the listening history needs to know about an episode that still exists.
public struct HistoryEpisodeState: Hashable, Sendable {
    public var title: String
    public var podcastTitle: String
    /// `itunes:subtitle` (N83).
    public var subtitle: String?
    public var duration: TimeInterval?
    public var playbackPosition: TimeInterval
    public var isPlayed: Bool

    public init(
        title: String, podcastTitle: String, subtitle: String?, duration: TimeInterval?,
        playbackPosition: TimeInterval, isPlayed: Bool
    ) {
        self.title = title
        self.podcastTitle = podcastTitle
        self.subtitle = subtitle
        self.duration = duration
        self.playbackPosition = playbackPosition
        self.isPlayed = isPlayed
    }
}

/// One row of the listening history: an episode that was started (N82).
public struct HistoryEntry: Hashable, Sendable, Identifiable {
    public var id: EpisodeID
    public var podcast: PodcastID?
    /// Current titles; the last session's snapshot once the episode is gone.
    public var title: String
    public var podcastTitle: String
    public var subtitle: String?
    /// The start of the day its last session began (A70).
    public var day: Date
    /// The end of its last session; rows are sorted by it.
    public var lastActiveAt: Date
    /// The playlist its last session played in, if that still is a tag (A72).
    public var lastPlaylist: PlaylistID?
    public var duration: TimeInterval?
    /// What played in all sessions together, merged and within the duration (A71).
    public var heard: [ClosedRange<TimeInterval>]
    /// The episode still exists: it has actions.
    public var isAvailable: Bool
    /// Started (a listening position) and not played (A73).
    public var isUnfinished: Bool
    /// The podcast's playlists, last known state (N85); for the filter.
    public var podcastPlaylists: Set<PlaylistID>
    /// All of the podcast's playlists are hidden: not under "Alle" (N84).
    public var podcastIsHidden: Bool

    /// The part of the episode that played, 0…1; `nil` without a duration.
    public var heardFraction: Double? {
        guard let duration, duration > 0 else { return nil }
        return heard.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) } / duration
    }
}

/// A day of the listening history, newest first.
public struct HistoryDay: Hashable, Sendable, Identifiable {
    /// The start of the day.
    public var id: Date
    /// Wall-clock listening time of the day's sessions of the episodes shown (A70, N55).
    public var listenedSeconds: TimeInterval
    public var entries: [HistoryEntry]

    public init(id: Date, listenedSeconds: TimeInterval, entries: [HistoryEntry]) {
        self.id = id
        self.listenedSeconds = listenedSeconds
        self.entries = entries
    }
}

/// What the listening history shows: playlist chips, "Nicht beendet" and the search.
public struct HistoryQuery: Hashable, Sendable {
    public var filter: PlaylistFilter
    public var onlyUnfinished: Bool
    public var search: String

    public init(filter: PlaylistFilter = .all, onlyUnfinished: Bool = false, search: String = "") {
        self.filter = filter
        self.onlyUnfinished = onlyUnfinished
        self.search = search
    }
}

/// The listening history (concept §4.12): every episode that was started, from the listening
/// log, one row per episode on the day it last played. Pure logic on values; the log itself
/// is never changed.
public enum ListeningHistory {
    /// One entry per episode in `sessions`, newest first. `podcastPlaylists`: each podcast's
    /// playlists by the last known state (N85); `hidden`: hidden playlists; `tags`: the
    /// playlists that exist and are tags (no "Alles").
    public static func entries(
        sessions: [ListeningRecord], episodes: [EpisodeID: HistoryEpisodeState],
        podcastPlaylists: [PodcastID: Set<PlaylistID>], hidden: Set<PlaylistID>, tags: Set<PlaylistID>,
        calendar: Calendar
    ) -> [HistoryEntry] {
        Dictionary(grouping: sessions, by: \.episode)
            .compactMap { id, sessions -> HistoryEntry? in
                guard let last = sessions.max(by: { ($0.endedAt, $0.startedAt) < ($1.endedAt, $1.startedAt) }) else { return nil }
                let state = episodes[id]
                let duration = state?.duration ?? last.episodeDuration
                let playlists = last.podcast.flatMap { podcastPlaylists[$0] }.map { $0.intersection(tags) } ?? []
                return HistoryEntry(
                    id: id, podcast: last.podcast,
                    title: state?.title ?? last.episodeTitle, podcastTitle: state?.podcastTitle ?? last.podcastTitle,
                    subtitle: state?.subtitle,
                    day: calendar.startOfDay(for: last.startedAt), lastActiveAt: last.endedAt,
                    lastPlaylist: last.playlist.flatMap { tags.contains($0) ? $0 : nil },
                    duration: duration, heard: heard(sessions, duration: duration),
                    isAvailable: state != nil,
                    isUnfinished: state.map { !$0.isPlayed && $0.playbackPosition > 0 } ?? false,
                    podcastPlaylists: playlists,
                    podcastIsHidden: HiddenPlaylists.hidesPodcast(in: playlists, hidden: hidden.intersection(tags)))
            }
            .sorted { ($0.lastActiveAt, $0.id.uuid.uuidString) > ($1.lastActiveAt, $1.id.uuid.uuidString) }
    }

    /// The entries `query` shows, grouped by day, newest first.
    public static func days(
        _ entries: [HistoryEntry], sessions: [ListeningRecord], query: HistoryQuery, calendar: Calendar
    ) -> [HistoryDay] {
        let shown = entries.filter { matches($0, query) }
        let shownIDs = Set(shown.map(\.id))
        var listened: [Date: TimeInterval] = [:]
        for session in sessions where shownIDs.contains(session.episode) {
            listened[calendar.startOfDay(for: session.startedAt), default: 0] += session.listenedSeconds
        }
        return Dictionary(grouping: shown, by: \.day)
            .map { day, entries in
                HistoryDay(
                    id: day, listenedSeconds: listened[day] ?? 0,
                    entries: entries.sorted { ($0.lastActiveAt, $0.id.uuid.uuidString) > ($1.lastActiveAt, $1.id.uuid.uuidString) })
            }
            .sorted { $0.id > $1.id }
    }

    /// "Vor einem Jahr" (A75): the episodes with a session that began on the same calendar day
    /// last year (on the 29th of February the 28th), the latest first; only `filter` applies.
    public static func yearAgo(
        _ entries: [HistoryEntry], sessions: [ListeningRecord], filter: PlaylistFilter, now: Date, calendar: Calendar
    ) -> [HistoryEntry] {
        guard let date = calendar.date(byAdding: .year, value: -1, to: now),
              let day = calendar.dateInterval(of: .day, for: date)
        else { return [] }
        var latest: [EpisodeID: Date] = [:]
        for session in sessions where day.contains(session.startedAt) && session.startedAt < day.end {
            latest[session.episode] = max(latest[session.episode] ?? .distantPast, session.startedAt)
        }
        return entries
            .filter { latest[$0.id] != nil && matches($0, HistoryQuery(filter: filter)) }
            .sorted { (latest[$0.id]!, $0.id.uuid.uuidString) > (latest[$1.id]!, $1.id.uuid.uuidString) }
    }

    /// The newest day in `interval` (A76: "Im Hörverlauf ›" from the statistics).
    public static func latestDay(in interval: DateInterval, of days: [HistoryDay]) -> Date? {
        days.map(\.id).filter { $0 >= interval.start && $0 < interval.end }.max()
    }

    // MARK: Helpers

    static func matches(_ entry: HistoryEntry, _ query: HistoryQuery) -> Bool {
        if query.onlyUnfinished, !entry.isUnfinished { return false }
        switch query.filter {
        case .all: if entry.podcastIsHidden { return false }
        case .playlist(let id): if !entry.podcastPlaylists.contains(id) { return false }
        case .withoutPlaylist: if !entry.podcastPlaylists.isEmpty { return false }
        }
        let words = query.search.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let text = [entry.title, entry.podcastTitle, entry.subtitle ?? ""].joined(separator: "\n")
        return words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Start to end position of each session, merged, within `duration` (A71).
    static func heard(_ sessions: [ListeningRecord], duration: TimeInterval?) -> [ClosedRange<TimeInterval>] {
        let limit = duration ?? .infinity
        let pieces = sessions
            .map { (max(0, min($0.startPosition, $0.endPosition)), min(limit, max($0.startPosition, $0.endPosition))) }
            .filter { $0.0 < $0.1 }
            .sorted { $0 < $1 }
        var merged: [ClosedRange<TimeInterval>] = []
        for (lower, upper) in pieces {
            if let last = merged.last, lower <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound...max(last.upperBound, upper)
            } else {
                merged.append(lower...upper)
            }
        }
        return merged
    }
}
