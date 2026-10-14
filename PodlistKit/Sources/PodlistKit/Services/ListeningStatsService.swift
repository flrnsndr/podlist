import Foundation
import SwiftData

/// Reads the listening log and the library for the statistics page (concept §4.11,
/// plan-hoerstatistik §7) and hands them to `ListeningStats` as values. Read-only.
/// A few thousand sessions a year: fetching on the main actor is fine; evaluating is not.
@MainActor
public final class ListeningStatsService {
    private let context: ModelContext
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private(set) var records: [ListeningRecord] = []
    private(set) var library = StatsLibrary()

    public init(context: ModelContext, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.context = context
        self.calendar = calendar
        self.now = now
    }

    /// Reads the log and the library again (when the page appears).
    public func reload() {
        let sessions = (try? context.fetch(FetchDescriptor<ListeningSession>(sortBy: [SortDescriptor(\.startedAt)]))) ?? []
        // A66: a session from "Alles" counts like a single episode (the podcast's playlists).
        let everything = ((try? context.fetch(FetchDescriptor<Playlist>())) ?? []).everything?.playlistID
        records = sessions.map(\.record).map { record in
            guard record.playlist != nil, record.playlist == everything else { return record }
            var single = record
            single.playlist = nil
            return single
        }
        library = makeLibrary()
    }

    /// The periods to page through, oldest first; the last one contains now.
    public func periods(_ kind: StatsPeriod.Kind) -> [StatsPeriod] {
        ListeningStats.periods(kind, sessions: records, calendar: calendar, now: now())
    }

    /// Evaluated off the main actor: a year of sessions takes a moment.
    public func report(for period: StatsPeriod) async -> StatsReport {
        await Self.evaluate(period, records, library, calendar, now())
    }

    @concurrent nonisolated private static func evaluate(
        _ period: StatsPeriod, _ records: [ListeningRecord], _ library: StatsLibrary, _ calendar: Calendar, _ now: Date
    ) async -> StatsReport {
        ListeningStats.report(for: period, sessions: records, library: library, calendar: calendar, now: now)
    }

    private func makeLibrary() -> StatsLibrary {
        let podcasts = (try? context.fetch(FetchDescriptor<Podcast>())) ?? []
        let playlists = (try? context.fetch(FetchDescriptor<Playlist>())) ?? []
        let entries = (try? context.fetch(FetchDescriptor<PlaylistEntry>())) ?? []
        let inProgress = (try? context.fetch(FetchDescriptor<Episode>(
            predicate: #Predicate { $0.playbackPosition > 0 && $0.playedAt == nil }))) ?? []

        var backlog: [UUID: TimeInterval] = [:]
        for episode in entries.compactMap(\.episode) where !episode.isPlayed {
            guard let duration = episode.duration else { continue }
            backlog[episode.uuid] = max(0, duration - episode.playbackPosition)
        }
        return StatsLibrary(
            podcasts: podcasts.map { podcast in
                StatsPodcast(
                    id: PodcastID(podcast.uuid), title: podcast.title,
                    playlists: (podcast.assignments ?? []).compactMap { $0.playlist?.playlistID },
                    categories: podcast.categories, subscribedAt: podcast.subscribedAt,
                    isSubscribed: podcast.isSubscribed,
                    episodesPublishedAt: (podcast.episodes ?? []).map(\.publishedAt))
            },
            playlists: playlists.tags.map {
                StatsPlaylist(id: $0.playlistID, name: $0.customName ?? $0.systemKey ?? "", colorKey: $0.colorKey, symbolName: $0.symbolName)
            },
            backlogSeconds: backlog.values.reduce(0, +),
            inProgress: inProgress.map {
                StatsInProgressEpisode(id: $0.episodeID, title: $0.title, podcastTitle: $0.podcast?.title ?? "", position: $0.playbackPosition)
            })
    }
}

extension ListeningSession {
    var record: ListeningRecord {
        ListeningRecord(
            startedAt: startedAt, endedAt: endedAt, listenedSeconds: listenedSeconds, contentSeconds: contentSeconds,
            skippedForwardSeconds: skippedForwardSeconds, skippedBackwardSeconds: skippedBackwardSeconds,
            startPosition: startPosition, endPosition: endPosition, endReason: endReason,
            episode: EpisodeID(episodeUUID), podcast: podcastUUID.map(PodcastID.init),
            playlist: playlistUUID.map(PlaylistID.init), episodeTitle: episodeTitle, podcastTitle: podcastTitle,
            episodePublishedAt: episodePublishedAt, episodeDuration: episodeDuration)
    }
}
