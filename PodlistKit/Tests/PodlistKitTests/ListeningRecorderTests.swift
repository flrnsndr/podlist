import Foundation
import SwiftData
import Testing
@testable import PodlistKit

/// The listening log, driven through the player's test hooks (plan-hoerstatistik §4.2).
@MainActor
struct ListeningRecorderTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private let container: ModelContainer
    private let clock = ManualClock(start: start)
    private let player: PlayerController
    private let upNext: UpNextService
    private let podcast: Podcast
    private let episode: Episode
    private let other: Episode
    private var context: ModelContext { container.mainContext }

    init() throws {
        container = try PodlistStore.makeContainer(inMemory: true)
        let library = LibraryService(container: container)
        let settings = try #require(UserDefaults(suiteName: "ListeningRecorderTests-\(UUID().uuidString)"))
        let recorder = ListeningRecorder(context: container.mainContext, now: { [clock] in clock.now })
        player = PlayerController(library: library, settings: settings, recorder: recorder)
        upNext = UpNextService(context: container.mainContext, library: library, player: player)
        podcast = Podcast(feedURL: URL(string: "https://example.com/feed.xml")!, title: "Sternengeschichten", subscribedAt: .distantPast)
        episode = Episode(guid: "1", title: "Folge 1", publishedAt: Date(timeIntervalSinceReferenceDate: 0), audioURL: URL(string: "https://cdn.invalid/1.mp3")!)
        other = Episode(guid: "2", title: "Folge 2", publishedAt: .distantPast, audioURL: URL(string: "https://cdn.invalid/2.mp3")!)
        episode.duration = 3_600
        other.duration = 3_600
        container.mainContext.insert(podcast)
        episode.podcast = podcast
        other.podcast = podcast
        try container.mainContext.save()
    }

    @Test func pausingClosesTheSessionWithSnapshots() throws {
        start(episode)
        listen(seconds: 10)
        player.pause()
        listen(seconds: 3, from: 10)  // ticks after the pause do not count

        // The first tick (after 0.5 s) opens the session; listening counts from there.
        let session = try #require(try sessions().only)
        #expect(session.listenedSeconds == 9.5)
        #expect(session.contentSeconds == 9.5)
        #expect(session.startPosition == 0.5 && session.endPosition == 10)
        #expect(session.startedAt == Self.start.addingTimeInterval(0.5))
        #expect(session.endedAt == Self.start.addingTimeInterval(10))
        #expect(session.endReason == .paused)
        #expect(session.episodeUUID == episode.uuid && session.podcastUUID == podcast.uuid)
        #expect(session.episodeTitle == "Folge 1" && session.podcastTitle == "Sternengeschichten")
        #expect(session.episodePublishedAt == episode.publishedAt)
        #expect(session.episodeDuration == 3_600)
        #expect(session.playlistUUID == nil, "a single episode")
    }

    @Test func aSessionInAPlaylistBlockKnowsThePlaylist() throws {
        let playlists = PlaylistService(context: context)
        let list = try playlists.createPlaylist(name: "Wissen", colorKey: "blue", symbolName: "star")
        try playlists.add(episode, to: list)
        upNext.playNow(list)
        player.currentItemBecameReady()
        listen(seconds: 10)
        player.pause()
        #expect(try sessions().only?.playlistUUID == list.uuid)
    }

    @Test func anAccidentalStartIsNotKept() throws {
        start(episode)
        listen(seconds: 3)
        player.pause()
        #expect(try sessions().isEmpty)
    }

    @Test func anOpenSessionIsWrittenEveryMinuteAsInterrupted() throws {
        start(episode)
        listen(seconds: 30)
        var session = try #require(try sessions().only)
        #expect(session.listenedSeconds == 5, "written once it is worth keeping")
        #expect(session.endReason == .interrupted, "until it closes; a killed app leaves it like this")

        listen(seconds: 40, from: 30)
        session = try #require(try sessions().only)
        #expect(session.listenedSeconds == 65, "written again a minute after the first write")

        player.pause()
        session = try #require(try sessions().only)
        #expect(session.listenedSeconds == 69.5)
        #expect(session.endReason == .paused)
    }

    @Test func theEndOfAnEpisodeFinishesItsSession() throws {
        start(episode, at: 3_580)
        listen(seconds: 10, from: 3_580)
        player.currentItemDidEnd()
        let session = try #require(try sessions().only)
        #expect(session.endReason == .finished)
        #expect(session.endPosition == 3_590)
    }

    @Test func theSleepTimerEndsTheSession() throws {
        start(episode)
        player.setSleepTimer(.duration(20))
        listen(seconds: 30)
        let session = try #require(try sessions().only)
        #expect(session.endReason == .sleepTimer)
        #expect(session.listenedSeconds == 19.5)
    }

    @Test func seeksAreCountedAsSkipsNotAsListening() throws {
        start(episode)
        listen(seconds: 10)
        player.skipForward()  // 30 s
        listen(seconds: 10, from: 40)
        player.skipBackward()  // 15 s
        listen(seconds: 10, from: 35)
        player.pause()
        let session = try #require(try sessions().only)
        #expect(session.listenedSeconds == 29.5)
        #expect(session.contentSeconds == 29.5)
        #expect(session.skippedForwardSeconds == 30)
        #expect(session.skippedBackwardSeconds == 15)
        #expect(session.endPosition == 45)
    }

    @Test func playingAnotherEpisodeClosesTheSessionAsSwitched() throws {
        start(episode)
        listen(seconds: 10)
        upNext.play(other)
        player.currentItemBecameReady()
        listen(seconds: 10)
        player.pause()

        let all = try sessions()
        #expect(all.map(\.episodeUUID) == [episode.uuid, other.uuid])
        #expect(all.map(\.endReason) == [.switched, .paused])
        #expect(all[0].endedAt == Self.start.addingTimeInterval(10), "ends at its last tick, not when the next one starts")
    }

    @Test func sessionsSurviveDeletedEpisodesAndPodcasts() throws {
        start(episode)
        listen(seconds: 10)
        player.pause()
        context.delete(podcast)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Episode>()) == 0)
        #expect(try sessions().only?.podcastTitle == "Sternengeschichten")
    }

    // MARK: Helpers

    private func start(_ episode: Episode, at position: TimeInterval = 0) {
        episode.playbackPosition = position
        upNext.play(episode)
        player.currentItemBecameReady()
    }

    /// Ticks every 0.5 s at 1× for `seconds`, starting at position `from`. The first tick of
    /// a session only opens it.
    private func listen(seconds: Int, from position: TimeInterval = 0) {
        for tick in 1...(seconds * 2) {
            clock.advance(by: 0.5)
            player.timeChanged(position + Double(tick) * 0.5)
        }
    }

    private func sessions() throws -> [ListeningSession] {
        try context.fetch(FetchDescriptor<ListeningSession>(sortBy: [SortDescriptor(\.startedAt)]))
    }
}

/// A clock the test moves by hand.
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(start: Date) { date = start }

    var now: Date { lock.withLock { date } }

    func advance(by seconds: TimeInterval) {
        lock.withLock { date += seconds }
    }
}

private extension Array {
    /// The single element, or nil if there are none or several.
    var only: Element? { count == 1 ? first : nil }
}
