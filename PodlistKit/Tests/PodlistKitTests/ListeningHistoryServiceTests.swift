import Foundation
import SwiftData
import Testing
@testable import PodlistKit

/// The listening history's view of the log and the library (concept §4.12).
@MainActor
struct ListeningHistoryServiceTests {
    nonisolated private static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try PodlistStore.makeContainer(inMemory: true)
    }

    @Test func mapsSessionsEpisodesAndPlaylistsToEntries() throws {
        let podcast = Podcast(feedURL: URL(string: "https://example.com/a.xml")!, title: "Lage der Nation", subscribedAt: Self.now)
        let news = Playlist(systemKey: "news", colorKey: "red", symbolName: "newspaper", displayOrder: 0)
        let everything = Playlist(systemKey: Playlist.everythingKey, colorKey: "gray", symbolName: "tray.full", displayOrder: -1)
        let item = episode("1", of: podcast, duration: 3_600, position: 600)
        item.subtitle = "Wahlrecht und Klimageld"
        context.insert(podcast)
        context.insert(news)
        context.insert(everything)
        context.insert(PlaylistAssignment(podcast: podcast, playlist: news, autoAdd: .bottom, createdAt: Self.now))
        session(item.uuid, podcast: podcast.uuid, playlist: everything.uuid, from: 0, to: 600)
        try context.save()

        let service = ListeningHistoryService(context: context, now: { Self.now })
        service.reload()

        let entry = try #require(service.entries.first)
        #expect(service.entries.count == 1)
        #expect(entry.id == item.episodeID && entry.isAvailable && entry.isUnfinished)
        #expect(entry.title == "1" && entry.podcastTitle == "Lage der Nation" && entry.subtitle == "Wahlrecht und Klimageld")
        #expect(entry.heard == [0...600] && entry.duration == 3_600)
        #expect(entry.podcastPlaylists == [news.playlistID])
        #expect(entry.lastPlaylist == nil, "\"Alles\" is no tag (A72)")
        #expect(service.episode(entry.id) == item)
    }

    /// N85, A74: an unsubscribed podcast counts with the playlists it had; deleted ones drop out.
    @Test func anUnsubscribedPodcastKeepsItsLastKnownPlaylists() throws {
        let podcast = Podcast(feedURL: URL(string: "https://example.com/a.xml")!, title: "Kinderfunk", subscribedAt: Self.now)
        podcast.isSubscribed = false
        let kids = Playlist(customName: "Kinder", colorKey: "pink", symbolName: "star", displayOrder: 0)
        kids.isHidden = true
        podcast.playlistUUIDsBeforeUnsubscribing = [kids.uuid, UUID()]
        context.insert(podcast)
        context.insert(kids)
        session(UUID(), podcast: podcast.uuid)
        try context.save()

        let service = ListeningHistoryService(context: context, now: { Self.now })
        service.reload()

        let entry = try #require(service.entries.first)
        #expect(!entry.isAvailable)
        #expect(entry.podcastPlaylists == [kids.playlistID])
        #expect(entry.podcastIsHidden)
        #expect(service.days(HistoryQuery()).isEmpty)
        #expect(service.days(HistoryQuery(filter: .playlist(kids.playlistID))).flatMap(\.entries).map(\.id) == [entry.id])
    }

    /// A subscribed podcast counts with its current assignments, never with old ones.
    @Test func aSubscribedPodcastCountsWithItsCurrentPlaylists() throws {
        let podcast = Podcast(feedURL: URL(string: "https://example.com/a.xml")!, title: "Kicker", subscribedAt: Self.now)
        let sport = Playlist(customName: "Sport", colorKey: "green", symbolName: "figure.run", displayOrder: 0)
        let old = Playlist(customName: "Alt", colorKey: "blue", symbolName: "clock", displayOrder: 1)
        podcast.playlistUUIDsBeforeUnsubscribing = [old.uuid]
        context.insert(podcast)
        context.insert(sport)
        context.insert(old)
        context.insert(PlaylistAssignment(podcast: podcast, playlist: sport, autoAdd: .bottom, createdAt: Self.now))
        session(UUID(), podcast: podcast.uuid)
        try context.save()

        let service = ListeningHistoryService(context: context, now: { Self.now })
        service.reload()

        #expect(service.entries.first?.podcastPlaylists == [sport.playlistID])
    }

    // MARK: Helpers

    private func episode(_ guid: String, of podcast: Podcast, duration: TimeInterval, position: TimeInterval) -> Episode {
        let episode = Episode(guid: guid, title: guid, publishedAt: Self.now, audioURL: URL(string: "https://example.com/\(guid).mp3")!)
        episode.podcast = podcast
        episode.duration = duration
        episode.playbackPosition = position
        context.insert(episode)
        return episode
    }

    private func session(_ episode: UUID, podcast: UUID?, playlist: UUID? = nil, from: TimeInterval = 0, to: TimeInterval = 60) {
        let session = ListeningSession(episodeUUID: episode, startedAt: Self.now.addingTimeInterval(-600))
        session.endedAt = Self.now
        session.listenedSeconds = to - from
        session.startPosition = from
        session.endPosition = to
        session.podcastUUID = podcast
        session.playlistUUID = playlist
        session.episodeTitle = "Snapshot"
        context.insert(session)
    }
}
