import Foundation
import SwiftData
import Testing
@testable import PodlistKit

/// The statistics page's view of the log and the library (plan-hoerstatistik §7).
@MainActor
struct ListeningStatsServiceTests {
    nonisolated private static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try PodlistStore.makeContainer(inMemory: true)
    }

    @Test func mapsSessionsAndTheLibraryToValues() throws {
        let podcast = Podcast(feedURL: URL(string: "https://example.com/feed.xml")!, title: "Lage der Nation", subscribedAt: Self.now)
        podcast.categories = ["News", "Politics"]
        let playlist = Playlist(systemKey: "news", colorKey: "red", symbolName: "newspaper", displayOrder: 0)
        let unplayed = episode("1", of: podcast, duration: 3_600, position: 600)
        let played = episode("2", of: podcast, duration: 1_800, position: 0)
        played.playedAt = Self.now
        context.insert(podcast)
        context.insert(playlist)
        context.insert(PlaylistAssignment(podcast: podcast, playlist: playlist, autoAdd: .bottom, createdAt: Self.now))
        // In two playlists: its rest counts once.
        let other = Playlist(customName: "Morgens", colorKey: "blue", symbolName: "sun.max", displayOrder: 1)
        context.insert(other)
        for (target, item) in [(playlist, unplayed), (other, unplayed), (playlist, played)] {
            context.insert(PlaylistEntry(playlist: target, episode: item, position: 0, addedAt: Self.now, origin: .manual))
        }
        let session = ListeningSession(episodeUUID: unplayed.uuid, startedAt: Self.now.addingTimeInterval(-600))
        session.endedAt = Self.now
        session.listenedSeconds = 500
        session.contentSeconds = 600
        session.podcastUUID = podcast.uuid
        session.playlistUUID = playlist.uuid
        session.podcastTitle = podcast.title
        session.endReason = .paused
        context.insert(session)
        try context.save()

        let service = ListeningStatsService(context: context, now: { Self.now })
        service.reload()

        #expect(service.records.count == 1)
        let record = try #require(service.records.first)
        #expect(record.episode == unplayed.episodeID && record.podcast == PodcastID(podcast.uuid))
        #expect(record.playlist == playlist.playlistID && record.endReason == .paused)
        #expect(record.listenedSeconds == 500 && record.contentSeconds == 600)

        let library = service.library
        #expect(library.backlogSeconds == 3_000)
        #expect(library.inProgress.map(\.id) == [unplayed.episodeID])
        let stats = try #require(library.podcasts.first)
        #expect(stats.playlists == [playlist.playlistID] && stats.categories == ["News", "Politics"])
        #expect(stats.episodesPublishedAt.count == 2)
        #expect(Set(library.playlists.map(\.name)) == ["news", "Morgens"])
        #expect(service.periods(.month).last == StatsPeriod(.month, containing: Self.now, calendar: .current))
    }

    @Test func sampleDataHasMonthsOfListening() async throws {
        try PlaylistService(context: context).insertDefaultPlaylists()
        try SampleData.insert(into: context, now: Self.now)
        let service = ListeningStatsService(context: context, now: { Self.now })
        service.reload()

        #expect(service.records.count > 500)
        #expect(service.records.allSatisfy { $0.endedAt <= Self.now })
        #expect(service.periods(.month).count == 14)
        #expect(service.periods(.year).count == 2)
        #expect(Set(service.records.map(\.endReason)).isSuperset(of: [.finished, .paused, .sleepTimer]))
        // A riser and one that cooled off, so the UI tests and previews show those cards too.
        let year = await service.report(for: .year(2026))
        #expect(year.insights.contains { if case let .riser(change) = $0 { change.podcast.title == "Hotel Matze" } else { false } })
        #expect(year.insights.contains { if case let .cooled(change) = $0 { change.podcast.title == "Baywatch Berlin" } else { false } })
    }

    private func episode(_ guid: String, of podcast: Podcast, duration: TimeInterval, position: TimeInterval) -> Episode {
        let episode = Episode(guid: guid, title: "Folge \(guid)", publishedAt: Self.now, audioURL: URL(string: "https://cdn.invalid/\(guid).mp3")!)
        episode.duration = duration
        episode.playbackPosition = position
        episode.podcast = podcast
        return episode
    }
}
