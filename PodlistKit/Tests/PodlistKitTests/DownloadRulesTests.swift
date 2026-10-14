import Foundation
import Testing
@testable import PodlistKit

/// What the automatic download loads (N31, N33, A38, A39), when a played download is
/// deleted (N32, A37) and the storage overview (concept §4.7).
struct DownloadRulesTests {
    private static let gigabyte: Int64 = 1_000_000_000

    private func entry(_ id: EpisodeID, played: Bool = false, state: DownloadState = .none) -> AutoDownloadEntry {
        AutoDownloadEntry(episode: id, isPlayed: played, state: state)
    }

    // MARK: Automatic downloads

    @Test func loadsEveryUnplayedEpisodeNotYetLoadedInPlaylistOrder() {
        let (a, b, c, d, e) = (EpisodeID(), EpisodeID(), EpisodeID(), EpisodeID(), EpisodeID())
        let entries = [
            entry(a), entry(b, played: true), entry(c, state: .downloaded),
            entry(d, state: .queued), entry(e),
        ]
        let ids = DownloadRules.automaticDownloads(entries, availableCapacity: 5 * Self.gigabyte, isPaused: false)
        #expect(ids == [a, e])
    }

    /// A38: what failed is not retried automatically.
    @Test func failedDownloadsAreNotRetried() {
        let a = EpisodeID()
        let ids = DownloadRules.automaticDownloads([entry(a, state: .failed)], availableCapacity: 5 * Self.gigabyte, isPaused: false)
        #expect(ids.isEmpty)
    }

    /// An episode in two auto-download playlists is loaded once.
    @Test func episodeInTwoPlaylistsLoadsOnce() {
        let (a, b) = (EpisodeID(), EpisodeID())
        let ids = DownloadRules.automaticDownloads([entry(a), entry(b), entry(a)], availableCapacity: 5 * Self.gigabyte, isPaused: false)
        #expect(ids == [a, b])
    }

    /// N33: below 1 GB free nothing starts automatically; an unknown capacity does not block.
    @Test(arguments: [
        (Int64?.some(999_999_999), false),
        (Int64?.some(1_000_000_000), true),
        (Int64?.none, true),
    ])
    func lowStorageStopsAutomaticDownloads(capacity: Int64?, loads: Bool) {
        let ids = DownloadRules.automaticDownloads([entry(EpisodeID())], availableCapacity: capacity, isPaused: false)
        #expect(ids.isEmpty == !loads)
        #expect(DownloadRules.isLowOnStorage(availableCapacity: capacity) == !loads)
    }

    /// A39: paused means nothing starts.
    @Test func pausedStartsNothing() {
        let ids = DownloadRules.automaticDownloads([entry(EpisodeID())], availableCapacity: 5 * Self.gigabyte, isPaused: true)
        #expect(ids.isEmpty)
    }

    // MARK: Played downloads

    struct DeleteCase: CustomTestStringConvertible, Sendable {
        let name: String
        let isPlayed: Bool
        let state: DownloadState
        let isNowPlaying: Bool
        let deletesPlayed: Bool
        let expected: Bool
        var testDescription: String { name }
    }

    /// N32, A37: also in keep playlists (the playlist is not an input at all).
    @Test(arguments: [
        DeleteCase(name: "played and loaded", isPlayed: true, state: .downloaded, isNowPlaying: false, deletesPlayed: true, expected: true),
        DeleteCase(name: "unplayed", isPlayed: false, state: .downloaded, isNowPlaying: false, deletesPlayed: true, expected: false),
        DeleteCase(name: "still in the player", isPlayed: true, state: .downloaded, isNowPlaying: true, deletesPlayed: true, expected: false),
        DeleteCase(name: "setting off", isPlayed: true, state: .downloaded, isNowPlaying: false, deletesPlayed: false, expected: false),
        DeleteCase(name: "running download is cancelled", isPlayed: true, state: .downloading, isNowPlaying: false, deletesPlayed: true, expected: true),
        DeleteCase(name: "waiting download is cancelled", isPlayed: true, state: .queued, isNowPlaying: false, deletesPlayed: true, expected: true),
        DeleteCase(name: "nothing loaded", isPlayed: true, state: .none, isNowPlaying: false, deletesPlayed: true, expected: false),
        DeleteCase(name: "failed is cleared", isPlayed: true, state: .failed, isNowPlaying: false, deletesPlayed: true, expected: true),
    ])
    func playedDownloadIsDeleted(_ c: DeleteCase) {
        let result = DownloadRules.shouldDeletePlayedDownload(
            isPlayed: c.isPlayed, state: c.state, isNowPlaying: c.isNowPlaying, deletesPlayed: c.deletesPlayed)
        #expect(result == c.expected)
    }

    // MARK: Storage overview

    @Test func summaryAddsUpByPodcastLargestFirst() {
        let (small, large) = (PodcastID(), PodcastID())
        let downloads = [
            DownloadedEpisode(episode: EpisodeID(), podcast: small, podcastTitle: "Hotel Matze", bytes: 100, isPlayed: true),
            DownloadedEpisode(episode: EpisodeID(), podcast: large, podcastTitle: "Lage der Nation", bytes: 300, isPlayed: false),
            DownloadedEpisode(episode: EpisodeID(), podcast: large, podcastTitle: "Lage der Nation", bytes: 200, isPlayed: true),
        ]
        let summary = DownloadRules.summary(downloads)
        #expect(summary.totalBytes == 600)
        #expect(summary.playedBytes == 300)
        #expect(summary.playedCount == 2)
        #expect(summary.unplayedBytes == 300)
        #expect(summary.podcasts == [
            PodcastStorage(podcast: large, title: "Lage der Nation", bytes: 500, episodeCount: 2, playedCount: 1),
            PodcastStorage(podcast: small, title: "Hotel Matze", bytes: 100, episodeCount: 1, playedCount: 1),
        ])
    }

    /// Same size: alphabetical, so the list does not jump.
    @Test func summaryTiesSortByTitle() {
        let downloads = [
            DownloadedEpisode(episode: EpisodeID(), podcast: PodcastID(), podcastTitle: "b", bytes: 10, isPlayed: false),
            DownloadedEpisode(episode: EpisodeID(), podcast: PodcastID(), podcastTitle: "A", bytes: 10, isPlayed: false),
        ]
        #expect(DownloadRules.summary(downloads).podcasts.map(\.title) == ["A", "b"])
    }

    /// The "Downloads" section sorts by size (largest first, the default) or by name.
    @Test func podcastsSortBySizeOrName() {
        let podcasts = [
            PodcastStorage(podcast: PodcastID(), title: "Zeit Verbrechen", bytes: 100, episodeCount: 1),
            PodcastStorage(podcast: PodcastID(), title: "Das Podcast Ufo", bytes: 900, episodeCount: 3),
            PodcastStorage(podcast: PodcastID(), title: "apokalypse & Filterkaffee", bytes: 400, episodeCount: 2),
            PodcastStorage(podcast: PodcastID(), title: "Lage der Nation", bytes: 400, episodeCount: 2),
        ]
        #expect(PodcastStorageSort.allCases.first == .size)
        #expect(DownloadRules.sorted(podcasts, by: .size).map(\.title)
            == ["Das Podcast Ufo", "apokalypse & Filterkaffee", "Lage der Nation", "Zeit Verbrechen"])
        #expect(DownloadRules.sorted(podcasts, by: .name).map(\.title)
            == ["apokalypse & Filterkaffee", "Das Podcast Ufo", "Lage der Nation", "Zeit Verbrechen"])
    }

    @Test func emptySummary() {
        let summary = DownloadRules.summary([])
        #expect(summary.totalBytes == 0)
        #expect(summary.podcasts.isEmpty)
    }
}
