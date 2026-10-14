import Foundation
import SwiftData

/// Reads the listening log and the library for the listening history (concept §4.12) and
/// hands them to `ListeningHistory` as values. Read-only, like `ListeningStatsService`: a few
/// thousand sessions a year fit on the main actor.
@MainActor
public final class ListeningHistoryService {
    private let context: ModelContext
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    public private(set) var sessions: [ListeningRecord] = []
    /// Newest first.
    public private(set) var entries: [HistoryEntry] = []
    private var episodes: [EpisodeID: Episode] = [:]

    public init(context: ModelContext, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.context = context
        self.calendar = calendar
        self.now = now
    }

    /// Reads the log and the library again (when the page appears or a session changed).
    public func reload() {
        let stored = (try? context.fetch(FetchDescriptor<ListeningSession>())) ?? []
        sessions = stored.map(\.record)
        let ids = Array(Set(stored.map(\.episodeUUID)))
        let found = (try? context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { ids.contains($0.uuid) }))) ?? []
        episodes = Dictionary(found.map { ($0.episodeID, $0) }, uniquingKeysWith: { first, _ in first })

        let playlists = ((try? context.fetch(FetchDescriptor<Playlist>())) ?? []).tags
        let podcasts = (try? context.fetch(FetchDescriptor<Podcast>())) ?? []
        entries = ListeningHistory.entries(
            sessions: sessions,
            episodes: episodes.mapValues(\.historyState),
            podcastPlaylists: Dictionary(podcasts.map { (PodcastID($0.uuid), $0.lastKnownPlaylists) }, uniquingKeysWith: { first, _ in first }),
            hidden: Set(playlists.filter(\.isHidden).map(\.playlistID)),
            tags: Set(playlists.map(\.playlistID)),
            calendar: calendar)
    }

    public func days(_ query: HistoryQuery) -> [HistoryDay] {
        ListeningHistory.days(entries, sessions: sessions, query: query, calendar: calendar)
    }

    /// "Vor einem Jahr" (A75).
    public func yearAgo(filter: PlaylistFilter) -> [HistoryEntry] {
        ListeningHistory.yearAgo(entries, sessions: sessions, filter: filter, now: now(), calendar: calendar)
    }

    /// The episode of a row; `nil` once it is gone.
    public func episode(_ id: EpisodeID) -> Episode? { episodes[id] }
}

extension Episode {
    var historyState: HistoryEpisodeState {
        HistoryEpisodeState(
            title: title, podcastTitle: podcast?.title ?? "", subtitle: subtitle, duration: duration,
            playbackPosition: playbackPosition, isPlayed: isPlayed)
    }
}

extension Podcast {
    /// Its playlists by the last known state (N85): the assignments while subscribed, the ones
    /// it had before unsubscribing afterwards (A74).
    var lastKnownPlaylists: Set<PlaylistID> {
        isSubscribed
            ? Set((assignments ?? []).compactMap { $0.playlist?.playlistID })
            : Set(playlistUUIDsBeforeUnsubscribing.map(PlaylistID.init))
    }
}
