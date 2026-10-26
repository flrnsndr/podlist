import AVFoundation
import Foundation
import SwiftData
import Synchronization
import Testing
@testable import PodlistKit

/// Integration tests for downloads (concept §4.7, ADR 0007): a `Downloader` on an ephemeral
/// session with a stubbed network, files in a temporary directory, an in-memory store.
@MainActor
struct DownloadServiceTests {
    private let container: ModelContainer
    private let routes = StubURLProtocol.Routes()
    private let files: DownloadFiles
    private let settings: UserDefaults
    private let capacity = Capacity()
    private let downloads: DownloadService
    private let library: LibraryService
    private let playlists: PlaylistService
    private let podcast: Podcast
    private var context: ModelContext { container.mainContext }
    private static let audio = Data(repeating: 7, count: 4_096)

    /// Free bytes the service sees; 5 GB unless a test changes it.
    final class Capacity: Sendable {
        private let value = Mutex<Int64?>(5_000_000_000)
        var bytes: Int64? {
            get { value.withLock { $0 } }
            set { value.withLock { $0 = newValue } }
        }
    }

    init() throws {
        container = try PodlistStore.makeContainer(inMemory: true)
        files = DownloadFiles(directory: URL.temporaryDirectory.appending(path: "DownloadServiceTests-\(UUID().uuidString)"))
        settings = try #require(UserDefaults(suiteName: "DownloadServiceTests-\(UUID().uuidString)"))
        downloads = Self.makeService(container: container, routes: routes, files: files, settings: settings, capacity: capacity)
        library = LibraryService(container: container, downloads: downloads)
        playlists = PlaylistService(context: container.mainContext, downloads: downloads)
        podcast = Podcast(feedURL: URL(string: "https://example.com/feed.xml")!, title: "Lage der Nation", subscribedAt: .distantPast)
        container.mainContext.insert(podcast)
        try container.mainContext.save()
    }

    private static func makeService(
        container: ModelContainer, routes: StubURLProtocol.Routes, files: DownloadFiles, settings: UserDefaults, capacity: Capacity
    ) -> DownloadService {
        DownloadService(
            context: container.mainContext,
            downloader: Downloader(configuration: StubURLProtocol.configuration(routes: routes), files: files),
            files: files, settings: settings, availableCapacity: { capacity.bytes })
    }

    // MARK: By hand

    @Test func downloadingStoresTheFileUnderTheEpisodesName() async throws {
        let episode = try makeEpisode("a")
        downloads.download(episode)
        #expect(episode.downloadState == .queued)

        try await waitUntil { episode.downloadState == .downloaded }
        let url = try #require(downloads.playableFileURL(for: episode))
        #expect(try Data(contentsOf: url) == Self.audio)
        #expect(episode.localFileName == "\(episode.uuid.uuidString).mp3")
        #expect(episode.fileSize == Int64(Self.audio.count), "the real size replaces the feed's")
        #expect(downloads.progress[episode.uuid] == nil)
    }

    @Test func requestsFollowTheCellularAndLowDataSettings() async throws {
        downloads.allowsCellular = false
        downloads.allowsLowDataMode = true
        let episode = try makeEpisode("a")
        downloads.download(episode)
        try await waitUntil { episode.downloadState == .downloaded }
        let request = try #require(routes.requests.last)
        #expect(!request.allowsCellularAccess)
        #expect(request.allowsConstrainedNetworkAccess)
    }

    /// A38: a failure keeps its reason and waits for "Erneut versuchen".
    @Test func aFailedDownloadCanBeRetried() async throws {
        let episode = try makeEpisode("a", status: 404)
        downloads.download(episode)
        try await waitUntil { episode.downloadState == .failed }
        #expect(downloads.failures[episode.uuid] == .notFound)
        #expect(downloads.playableFileURL(for: episode) == nil)

        serve(episode.audioURL)
        downloads.download(episode)
        try await waitUntil { episode.downloadState == .downloaded }
        #expect(downloads.failures[episode.uuid] == nil)
    }

    @Test func deletingRemovesTheFile() async throws {
        let episode = try makeEpisode("a")
        downloads.download(episode)
        try await waitUntil { episode.downloadState == .downloaded }
        let url = try #require(downloads.playableFileURL(for: episode))

        downloads.delete([episode])
        #expect(episode.downloadState == .none)
        #expect(episode.localFileName == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func deletingAllPlayedKeepsUnplayed() async throws {
        let (played, unplayed) = (try makeEpisode("a"), try makeEpisode("b"))
        downloads.download(played)
        downloads.download(unplayed)
        try await waitUntil { played.downloadState == .downloaded && unplayed.downloadState == .downloaded }
        downloads.deletesPlayed = false
        try library.markPlayed(played)
        #expect(played.downloadState == .downloaded, "setting off: nothing deleted on its own")

        downloads.deleteAllPlayed()
        #expect(played.downloadState == .none)
        #expect(unplayed.downloadState == .downloaded)
    }

    /// Cancelling and downloading again at once: the cancel never hits the new task.
    @Test func cancellingAndDownloadingAgainLoads() async throws {
        let episode = try makeEpisode("a")
        downloads.download(episode)
        downloads.delete([episode])
        downloads.download(episode)
        try await waitUntil { episode.downloadState == .downloaded }
        #expect(downloads.playableFileURL(for: episode) != nil)
    }

    /// The first task finished before its cancel came, and its event arrives after the new
    /// task's file is in place (both share the episode's file name): the file stays.
    @Test func aCancelThatCameTooLateKeepsTheNewFile() async throws {
        let episode = try makeEpisode("a")
        let fileURL = files.url(forFileNamed: "\(episode.uuid.uuidString).mp3")
        downloads.download(episode)
        waitBlockingMainActor { files.existingFileName(for: episode.uuid) != nil }
        downloads.delete([episode])
        let newer = Data(repeating: 8, count: 4_096)
        routes.set(episode.audioURL, .init(headers: ["Content-Type": "audio/mpeg"], body: newer))
        downloads.download(episode)
        waitBlockingMainActor { (try? Data(contentsOf: fileURL)) == newer }

        try await waitUntil { episode.downloadState == .downloaded }
        let url = try #require(downloads.playableFileURL(for: episode))
        #expect(try Data(contentsOf: url) == newer)
    }

    @Test func deletingWhileLoadingLeavesNoFile() async throws {
        let episode = try makeEpisode("a")
        downloads.download(episode)
        downloads.delete([episode])
        try await Task.sleep(for: .milliseconds(300))
        #expect(episode.downloadState == .none)
        #expect(files.existingFileName(for: episode.uuid) == nil)
    }

    // MARK: Automatic (N31, N33)

    /// N31: turning auto-download on loads every unplayed episode already in the playlist.
    @Test func autoDownloadLoadsEveryUnplayedEpisode() async throws {
        let playlist = try makePlaylist(autoDownload: false)
        let (a, b) = (try makeEpisode("a"), try makeEpisode("b"))
        for episode in [a, b] { try playlists.add(episode, to: playlist) }

        try playlists.setAutoDownload(true, of: playlist)
        try await waitUntil { a.downloadState == .downloaded && b.downloadState == .downloaded }
    }

    /// A keep playlist with auto-download loads its played episodes too, and keeps them
    /// (Florian, after N101); a played episode somewhere else is not loaded.
    @Test func aKeepPlaylistWithAutoDownloadLoadsPlayedEpisodes() async throws {
        let keep = try makePlaylist(autoDownload: false)
        try playlists.setPlayedPolicy(.keep, of: keep)
        let (played, elsewhere) = (try makeEpisode("a"), try makeEpisode("b"))
        try playlists.add(played, to: keep)
        try library.markPlayed(played)
        try library.markPlayed(elsewhere)

        try playlists.setAutoDownload(true, of: keep)
        try await waitUntil { played.downloadState == .downloaded }
        #expect(elsewhere.downloadState == .none)
        downloads.evaluate()
        #expect(played.downloadState == .downloaded, "a check does not delete it again")
    }

    @Test func anEpisodeAddedToAnAutoDownloadPlaylistIsLoaded() async throws {
        let playlist = try makePlaylist(autoDownload: true)
        let episode = try makeEpisode("a")
        try playlists.add(episode, to: playlist)
        try await waitUntil { episode.downloadState == .downloaded }
    }

    @Test func playlistsWithoutAutoDownloadLoadNothing() async throws {
        let playlist = try makePlaylist(autoDownload: false)
        let episode = try makeEpisode("a")
        try playlists.add(episode, to: playlist)
        downloads.evaluate()
        #expect(episode.downloadState == .none)
    }

    /// N33: below 1 GB nothing starts automatically, by hand still works.
    @Test func lowStorageStopsOnlyAutomaticDownloads() async throws {
        capacity.bytes = 500_000_000
        let playlist = try makePlaylist(autoDownload: false)
        let episode = try makeEpisode("a")
        try playlists.add(episode, to: playlist)
        try playlists.setAutoDownload(true, of: playlist)
        #expect(episode.downloadState == .none)
        #expect(downloads.isLowOnStorage)

        downloads.download(episode)
        try await waitUntil { episode.downloadState == .downloaded }
    }

    /// A40: leaving the playlist or turning auto-download off keeps what is loaded.
    @Test func turningAutoDownloadOffOrRemovingKeepsTheDownload() async throws {
        let playlist = try makePlaylist(autoDownload: false)
        let (a, b) = (try makeEpisode("a"), try makeEpisode("b"))
        try playlists.add(a, to: playlist)
        try playlists.add(b, to: playlist)
        try playlists.setAutoDownload(true, of: playlist)
        try await waitUntil { a.downloadState == .downloaded && b.downloadState == .downloaded }

        try playlists.remove(a, from: playlist)
        try playlists.setAutoDownload(false, of: playlist)
        #expect(a.downloadState == .downloaded)
        #expect(b.downloadState == .downloaded)
    }

    /// Concept §6.3: a refresh adds a new episode to an auto-download playlist, which loads it.
    @Test func aNewEpisodeFromARefreshIsLoaded() async throws {
        let feedURL = URL(string: "https://example.com/auto/feed.xml")!
        let library = LibraryService(
            container: container, loader: FeedLoader(session: StubURLProtocol.session(routes: routes)), downloads: downloads)
        routes.set(feedURL, .init(body: Data(Self.feed(guids: ["n1"]).utf8)))
        let subscribed = try #require(try await library.subscribe(to: feedURL))
        let playlist = try makePlaylist(autoDownload: true)
        try playlists.assign(subscribed, to: playlist, autoAdd: .top)
        serve(URL(string: "https://cdn.example.com/n1.mp3")!)
        serve(URL(string: "https://cdn.example.com/n2.mp3")!)

        routes.set(feedURL, .init(body: Data(Self.feed(guids: ["n2", "n1"]).utf8)))
        await library.refreshAll()
        let newest = try #require(try context.fetch(FetchDescriptor<Episode>()).first { $0.guid == "n2" })
        try await waitUntil { newest.downloadState == .downloaded }
    }

    /// N88: "Alles" loads every unplayed episode it has, also of playlists that do not load
    /// themselves; a playlist left out of it loads once it is chosen again.
    @Test func everythingWithAutoDownloadLoadsItsEpisodes() async throws {
        let everything = try makeEverything()
        try playlists.setAutoDownload(false, of: everything)
        let chosen = try makePlaylist(autoDownload: false)
        let leftOut = try makePlaylist(autoDownload: false)
        try playlists.setExcluded(true, playlist: leftOut)
        try playlists.setPlayedPolicy(.keep, of: chosen)
        let (a, played, other) = (try makeEpisode("a"), try makeEpisode("b"), try makeEpisode("c"))
        try playlists.add(a, to: chosen)
        try playlists.add(played, to: chosen)
        try library.markPlayed(played)
        try playlists.add(other, to: leftOut)

        try playlists.setAutoDownload(true, of: everything)
        try await waitUntil { a.downloadState == .downloaded }
        #expect(played.downloadState == .none)
        #expect(other.downloadState == .none, "left out of Alles")

        try playlists.setExcluded(false, playlist: leftOut)
        try await waitUntil { other.downloadState == .downloaded }
    }

    // MARK: Pause (A39)

    @Test func pausingHoldsDownloadsUntilResumed() async throws {
        await downloads.pause()
        let episode = try makeEpisode("a")
        downloads.download(episode)
        try await Task.sleep(for: .milliseconds(200))
        #expect(episode.downloadState == .queued)
        #expect(routes.requests.isEmpty)

        let restarted = Self.makeService(container: container, routes: routes, files: files, settings: settings, capacity: capacity)
        #expect(restarted.isPaused, "the pause survives a restart")

        downloads.resume()
        try await waitUntil { episode.downloadState == .downloaded }
    }

    // MARK: Played downloads (N32, A37)

    @Test func markingPlayedDeletesTheDownloadAlsoInKeepPlaylists() async throws {
        let playlist = try makePlaylist(autoDownload: false)
        try playlists.setPlayedPolicy(.keep, of: playlist)
        let episode = try makeEpisode("a")
        try playlists.add(episode, to: playlist)
        downloads.download(episode)
        try await waitUntil { episode.downloadState == .downloaded }

        try library.markPlayed(episode)
        #expect(episode.downloadState == .none)
        #expect((playlist.entries ?? []).contains { $0.episode == episode }, "the entry stays")
    }

    /// A keep playlist that downloads automatically keeps a played episode's file, as long as
    /// the episode is in it and the playlist stays like that (Florian, after N101).
    @Test func aKeepPlaylistWithAutoDownloadKeepsAPlayedDownload() async throws {
        var pairs: [(Playlist, Episode)] = []
        for guid in ["a", "b", "c", "d"] {
            let keep = try makePlaylist(autoDownload: true)
            try playlists.setPlayedPolicy(.keep, of: keep)
            let episode = try makeEpisode(guid)
            try playlists.add(episode, to: keep)
            pairs.append((keep, episode))
        }
        let episodes = pairs.map(\.1)
        try await waitUntil { episodes.allSatisfy { $0.downloadState == .downloaded } }
        for episode in episodes { try library.markPlayed(episode) }
        #expect(episodes.allSatisfy { $0.downloadState == .downloaded })

        try playlists.remove(pairs[0].1, from: pairs[0].0)
        #expect(pairs[0].1.downloadState == .none, "no longer in the playlist")
        try playlists.setPlayedPolicy(.remove, of: pairs[1].0)
        #expect(pairs[1].1.downloadState == .none, "no longer a keep playlist")
        try playlists.setAutoDownload(false, of: pairs[2].0)
        #expect(pairs[2].1.downloadState == .none, "no longer downloads automatically")
        try playlists.delete(pairs[3].0)
        #expect(pairs[3].1.downloadState == .none, "the playlist is gone")
    }

    /// A played download that is left over (the app ended while ⏭ could still be undone, A81)
    /// goes at the next check, e.g. after the launch.
    @Test func aLeftOverPlayedDownloadGoesAfterTheLaunch() async throws {
        let episode = try makeEpisode("a")
        downloads.download(episode)
        try await waitUntil { episode.downloadState == .downloaded }
        episode.playedAt = .distantPast  // played without the rule running
        try context.save()

        await downloads.restoreAfterLaunch()
        #expect(episode.downloadState == .none)
    }

    @Test func thePlayingEpisodeKeepsItsDownloadUntilItLeavesThePlayer() async throws {
        let player = PlayerController(library: library, downloads: downloads, settings: settings)
        let upNext = UpNextService(context: context, library: library, player: player)
        let episode = try makeEpisode("a")
        downloads.download(episode)
        try await waitUntil { episode.downloadState == .downloaded }
        upNext.play(episode)

        try library.saveProgress(episode, position: 3_590)
        #expect(episode.isPlayed, "almost at the end counts as played")
        try library.applyPlayedPolicy(to: episode)
        #expect(episode.downloadState == .downloaded, "still in the player")

        upNext.play(try makeEpisode("b"))
        #expect(episode.downloadState == .none)
    }

    /// N101, A81: the download of a skipped episode stays while ⏭ can be undone.
    @Test func aSkippedEpisodeKeepsItsDownloadUntilTheUndoIsGone() async throws {
        let player = PlayerController(library: library, downloads: downloads, settings: settings)
        let upNext = UpNextService(context: context, library: library, player: player)
        let playlist = try makePlaylist(autoDownload: false)
        let (a, b, c) = (try makeEpisode("a"), try makeEpisode("b"), try makeEpisode("c"))
        for episode in [a, b, c] { try playlists.add(episode, to: playlist) }
        downloads.download(a)
        downloads.download(b)
        try await waitUntil { a.downloadState == .downloaded && b.downloadState == .downloaded }
        upNext.playNow(playlist)

        upNext.skip()
        #expect(a.isPlayed)
        #expect(a.downloadState == .downloaded, "undo may still bring it back")
        upNext.undo(try #require(upNext.undoableChange))
        #expect(player.episode == a)
        #expect(a.downloadState == .downloaded)
        #expect(downloads.playableFileURL(for: a) != nil)

        upNext.skip()
        upNext.dismissUndo()
        #expect(a.downloadState == .none, "the undo is gone: the played download goes (N32)")

        upNext.skip()
        #expect(b.downloadState == .downloaded)
        upNext.playNow(playlist)  // a replacement ends the undo of ⏭
        #expect(b.downloadState == .none)
    }

    /// A37: an episode that ends loses its download once the player let go of it.
    @Test func anEpisodeThatEndsLosesItsDownload() async throws {
        let player = PlayerController(library: library, downloads: downloads, settings: settings)
        let upNext = UpNextService(context: context, library: library, player: player)
        let episode = try makeEpisode("a")
        downloads.download(episode)
        try await waitUntil { episode.downloadState == .downloaded }
        upNext.play(episode)

        upNext.episodeDidEnd(episode)
        #expect(episode.isPlayed)
        #expect(episode.downloadState == .none)
    }

    // MARK: Player (A36)

    @Test func thePlayerPlaysTheFileAndStreamsWhenItIsDeleted() async throws {
        let player = PlayerController(library: library, downloads: downloads, settings: settings)
        let upNext = UpNextService(context: context, library: library, player: player)
        let episode = try makeEpisode("a")
        downloads.download(episode)
        try await waitUntil { episode.downloadState == .downloaded }

        upNext.play(episode)
        #expect(player.currentURL == downloads.playableFileURL(for: episode))
        player.seek(to: 600)

        downloads.delete([episode])
        #expect(player.currentURL == episode.audioURL)
        #expect(player.currentTime == 600)
        #expect(player.wantsToPlay)
    }

    @Test func aStreamingEpisodeKeepsStreamingWhenItsDownloadFinishes() async throws {
        let player = PlayerController(library: library, downloads: downloads, settings: settings)
        let upNext = UpNextService(context: context, library: library, player: player)
        let episode = try makeEpisode("a")
        upNext.play(episode)
        downloads.download(episode)
        try await waitUntil { episode.downloadState == .downloaded }
        // The stream may have failed meanwhile (no network in tests); it never became the file.
        #expect(player.currentURL?.isFileURL != true)
        #expect(player.episode == episode)
    }

    // MARK: After a launch

    @Test func restoringStartsWaitingDownloadsAndForgetsMissingFiles() async throws {
        let waiting = try makeEpisode("a")
        waiting.downloadState = .downloading
        let missing = try makeEpisode("b")
        missing.downloadState = .downloaded
        missing.localFileName = "gone.mp3"
        try context.save()

        await downloads.restoreAfterLaunch()
        #expect(missing.downloadState == .none)
        #expect(missing.localFileName == nil)
        try await waitUntil { waiting.downloadState == .downloaded }
    }

    /// Finished while the app was not running: the file is there, the task is gone.
    @Test func restoringAdoptsAFileThatFinishedWhileTheAppWasNotRunning() async throws {
        let episode = try makeEpisode("a")
        episode.downloadState = .downloading
        try context.save()
        let temporary = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try Self.audio.write(to: temporary)
        _ = try files.moveIntoPlace(temporary, named: "\(episode.uuid.uuidString).mp3")

        await downloads.restoreAfterLaunch()
        #expect(episode.downloadState == .downloaded)
        #expect(episode.fileSize == Int64(Self.audio.count))
        #expect(routes.requests.isEmpty, "not loaded a second time")
    }

    // MARK: Helpers

    private static func feed(guids: [String]) -> String {
        let items = guids.enumerated().map { index, guid in
            """
            <item><guid>\(guid)</guid><title>\(guid)</title><pubDate>Mon, 0\(5 - index) Oct 2026 08:00:00 +0000</pubDate>
            <enclosure url="https://cdn.example.com/\(guid).mp3" length="1000" type="audio/mpeg"/></item>
            """
        }
        return """
            <?xml version="1.0" encoding="UTF-8"?><rss version="2.0"><channel><title>Auto</title>
            \(items.joined())
            </channel></rss>
            """
    }

    private func makePlaylist(autoDownload: Bool) throws -> Playlist {
        let playlist = try playlists.createPlaylist(name: "Politik", colorKey: "blue", symbolName: "building.columns")
        try playlists.setAutoDownload(autoDownload, of: playlist)
        return playlist
    }

    private func makeEverything() throws -> Playlist {
        try playlists.ensureEverything()
        return try #require(try context.fetch(FetchDescriptor<Playlist>()).everything)
    }

    private func makeEpisode(_ guid: String, status: Int = 200) throws -> Episode {
        let episode = Episode(
            guid: guid, title: guid.uppercased(), publishedAt: .distantPast,
            audioURL: URL(string: "https://cdn.example.com/\(guid).mp3")!)
        episode.duration = 3_600
        episode.fileSize = 50_000_000
        episode.podcast = podcast
        context.insert(episode)
        try context.save()
        serve(episode.audioURL, status: status)
        return episode
    }

    private func serve(_ url: URL, status: Int = 200) {
        routes.set(url, .init(status: status, headers: ["Content-Type": "audio/mpeg"], body: status == 200 ? Self.audio : Data()))
    }

    private func waitUntil(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Timed out", sourceLocation: sourceLocation)
    }

    /// Waits without yielding the main actor, so the service handles no download event meanwhile.
    private func waitBlockingMainActor(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) {
        for _ in 0..<250 {
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.02)
        }
        Issue.record("Timed out", sourceLocation: sourceLocation)
    }
}
