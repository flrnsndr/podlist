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

        // Queue: an episode in the player from a playlist, then a single episode and two playlists.
        let queue = try context.fetch(FetchDescriptor<QueueItem>(sortBy: [SortDescriptor(\.position)]))
        let nowPlaying = try #require(queue.first { $0.isNowPlaying })
        #expect(nowPlaying.playlist != nil)
        #expect((nowPlaying.episode?.playbackPosition ?? 0) > 0)
        let items = queue.filter { !$0.isNowPlaying }
        #expect(items.first?.episode != nil)
        #expect(items.compactMap(\.playlist).count >= 2)

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
}
