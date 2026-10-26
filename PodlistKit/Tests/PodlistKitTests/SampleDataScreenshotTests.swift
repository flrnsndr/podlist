import Foundation
import SwiftData
import Testing
@testable import PodlistKit

/// The made-up library behind the website screenshots (`-screenshots`): every screen it is
/// photographed on has something to show, in German and in English.
@MainActor
struct SampleDataScreenshotTests {
    nonisolated private static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)

    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try PodlistStore.makeContainer(inMemory: true)
    }

    @Test(arguments: [true, false])
    func everyScreenHasSomethingToShow(german: Bool) async throws {
        try PlaylistService(context: context).insertDefaultPlaylists()
        try SampleData.insertScreenshots(
            into: context, german: german, artwork: { URL(string: "https://example.com/\($0).png") }, now: Self.now)

        let podcasts = try context.fetch(FetchDescriptor<Podcast>())
        #expect(podcasts.count >= 8)
        #expect(podcasts.allSatisfy { $0.artworkURL != nil })
        #expect(!podcasts.contains { $0.title.hasPrefix("Lage der Nation") })

        // Queue (flat, ADR 0008): a started episode in the player, the rest of its playlist,
        // then a single episode and two more playlists taken over; no blocks.
        let queue = try context.fetch(FetchDescriptor<QueueItem>(sortBy: [SortDescriptor(\.position)]))
        let nowPlaying = try #require(queue.first { $0.isNowPlaying })
        #expect((nowPlaying.episode?.playbackPosition ?? 0) > 0)
        let items = queue.filter { !$0.isNowPlaying }
        #expect(items.count >= 8)
        #expect(items.allSatisfy { $0.episode != nil && $0.playlist == nil })
        #expect(Set(items.compactMap(\.episode)).count == items.count, "each episode once (N105)")

        // Player and episode details: the started episode has chapters (one with a link) and
        // show notes with timestamps.
        let playing = try #require(nowPlaying.episode)
        #expect(playing.chapters.count >= 4)
        #expect(playing.chaptersSource == .podlove)
        #expect(playing.chapters.contains { $0.linkURL != nil })
        #expect(playing.chapters.contains { $0.start < playing.playbackPosition }
            && playing.chapters.contains { $0.start > playing.playbackPosition })
        #expect(ShowNotesTimestamps.matches(in: HTMLText.plainText(fromHTML: playing.showNotes ?? "")).count >= 2)

        // Inbox: the episode from the website graphic, missing from both of its playlists.
        let floorNotes = try #require(podcasts.first { $0.title == (german ? "Plenarnotizen" : "Floor Notes") })
        #expect(floorNotes.assignments?.count == 2)
        let open = try context.fetch(FetchDescriptor<Episode>()).filter { $0.inboxAddedAt != nil && $0.inboxState == .open }
        #expect(open.count >= 3)
        #expect(open.contains { $0.podcast == floorNotes && ($0.playlistEntries ?? []).isEmpty })

        // Every playlist with podcasts has a place to continue from and episodes to show.
        let playlists = try context.fetch(FetchDescriptor<Playlist>()).filter { !($0.assignments ?? []).isEmpty }
        #expect(playlists.allSatisfy { ($0.entries ?? []).count >= 2 })

        // Listening stats under the made-up names.
        let stats = ListeningStatsService(context: context, now: { Self.now })
        stats.reload()
        #expect(stats.records.count > 500)
        let titles = Set(podcasts.map(\.title))
        let year = await stats.report(for: .year(2026))
        #expect(year.insights.contains { if case let .riser(change) = $0 { titles.contains(change.podcast.title) } else { false } })
    }

    /// Debug builds in the simulator start with this library (`insertSimulatorLibraryIfEmpty`),
    /// but only into a store without podcasts: one the user already filled stays as it is.
    @Test func simulatorLibraryFillsOnlyAStoreWithoutPodcasts() throws {
        try PlaylistService(context: context).insertDefaultPlaylists()
        let artwork: (String) -> URL? = { URL(string: "https://example.com/\($0).png") }
        #expect(try SampleData.insertSimulatorLibraryIfEmpty(into: context, german: true, artwork: artwork, now: Self.now))
        let podcasts = try context.fetch(FetchDescriptor<Podcast>())
        #expect(podcasts.count >= 8)
        let open = try context.fetch(FetchDescriptor<Episode>()).filter { $0.inboxAddedAt != nil && $0.inboxState == .open }
        #expect(!open.isEmpty)
        let tags = try context.fetch(FetchDescriptor<Playlist>()).filter { !$0.isEverything }
        #expect(tags.allSatisfy { ($0.entries ?? []).count >= 2 })

        let episodes = try context.fetchCount(FetchDescriptor<Episode>())
        #expect(try !SampleData.insertSimulatorLibraryIfEmpty(into: context, german: true, artwork: artwork, now: Self.now))
        #expect(try context.fetchCount(FetchDescriptor<Podcast>()) == podcasts.count)
        #expect(try context.fetchCount(FetchDescriptor<Episode>()) == episodes)
    }

    @Test func simulatorLibraryLeavesAStoreWithPodcastsAlone() throws {
        try PlaylistService(context: context).insertDefaultPlaylists()
        context.insert(Podcast(feedURL: URL(string: "https://example.com/own/feed.xml")!, title: "Own", subscribedAt: Self.now))
        try context.save()

        #expect(try !SampleData.insertSimulatorLibraryIfEmpty(
            into: context, german: false, artwork: { _ in nil }, now: Self.now))
        #expect(try context.fetch(FetchDescriptor<Podcast>()).map(\.title) == ["Own"])
        #expect(try context.fetchCount(FetchDescriptor<Episode>()) == 0)
    }

    @Test func screenshotArtworkFollowsTheRenderedCovers() throws {
        try PlaylistService(context: context).insertDefaultPlaylists()
        try SampleData.insertScreenshots(
            into: context, german: true, artwork: { URL(string: "file:///old/\($0).png") }, now: Self.now)
        let own = Podcast(feedURL: URL(string: "https://feeds.example.org/own.xml")!, title: "Own", subscribedAt: Self.now)
        own.artworkURL = URL(string: "https://feeds.example.org/own.png")
        context.insert(own)
        try context.save()

        try SampleData.updateScreenshotArtwork(in: context) { URL(string: "file:///new/\($0).png") }

        let podcasts = try context.fetch(FetchDescriptor<Podcast>())
        let morning = try #require(podcasts.first { $0.title == "Morgenlage" })
        #expect(morning.artworkURL == URL(string: "file:///new/morning.png"))
        #expect(podcasts.filter { $0 != own }.allSatisfy { $0.artworkURL?.path().hasPrefix("/new/") == true })
        #expect(own.artworkURL == URL(string: "https://feeds.example.org/own.png"))
    }
}
