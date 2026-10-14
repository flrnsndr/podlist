import AVFoundation
import Foundation
import MediaPlayer
import SwiftData
import Testing
@testable import PodlistKit

/// Player state rules that do not need real audio (the episode URL never loads).
@MainActor
struct PlayerControllerTests {
    private let container: ModelContainer
    private let library: LibraryService
    private let settings: UserDefaults
    private let player: PlayerController
    private let upNext: UpNextService
    private let episode: Episode

    init() throws {
        container = try PodlistStore.makeContainer(inMemory: true)
        library = LibraryService(container: container)
        settings = try #require(UserDefaults(suiteName: "PlayerControllerTests-\(UUID().uuidString)"))
        player = PlayerController(library: library, settings: settings)
        upNext = UpNextService(context: container.mainContext, library: library, player: player)
        episode = Episode(guid: "1", title: "E", publishedAt: .distantPast, audioURL: URL(string: "https://cdn.invalid/1.mp3")!)
        episode.duration = 3_600
        container.mainContext.insert(episode)
        try container.mainContext.save()
    }

    @Test func markingThePlayingEpisodePlayedResetsThePlayersPosition() {
        upNext.play(episode)
        player.seek(to: 600)
        #expect(player.currentTime == 600)

        player.markPlayed(episode)
        #expect(episode.isPlayed)
        #expect(episode.playbackPosition == 0)
        #expect(player.currentTime == 0, "a later progress save must not write 600 back (A8)")
        #expect(!player.wantsToPlay)
        player.saveProgress()
        #expect(episode.playbackPosition == 0)
    }

    @Test func markingAnotherEpisodePlayedDoesNotTouchThePlayer() throws {
        let other = Episode(guid: "2", title: "F", publishedAt: .distantPast, audioURL: URL(string: "https://cdn.invalid/2.mp3")!)
        container.mainContext.insert(other)
        upNext.play(episode)
        player.seek(to: 600)
        player.markPlayed(other)
        #expect(other.isPlayed)
        #expect(player.currentTime == 600)
        #expect(player.wantsToPlay)
    }

    #if os(iOS)
    // The audio session exists on iOS only (scripts/verify.sh package-ios).
    @Test func afterAnInterruptionOneTapPlaysAgain() async throws {
        upNext.play(episode)
        #expect(player.wantsToPlay)
        NotificationCenter.default.post(
            name: AVAudioSession.interruptionNotification, object: nil,
            userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        try await Task.sleep(for: .milliseconds(100))
        #expect(!player.wantsToPlay, "the system paused playback")

        player.togglePlayPause()
        #expect(player.wantsToPlay, "one tap on ▶ plays again")
    }
    #endif

    // MARK: After a restart (restored, nothing loaded yet)

    @Test func seekingBeforeTheFirstPlayAfterARestartIsKept() throws {
        episode.playbackPosition = 100
        try restoreAfterARestart()
        player.seek(to: 900)
        #expect(episode.playbackPosition == 900)

        player.resume()
        #expect(player.currentTime == 900)
        #expect(player.wantsToPlay)
    }

    @Test func resumingARestoredPlayedEpisodeMakesItUnplayed() throws {
        episode.playedAt = .distantPast
        episode.playbackPosition = 0
        try restoreAfterARestart()

        player.resume()
        #expect(!episode.isPlayed, "a manual start makes a played episode unplayed (N9)")
    }

    @Test func aStatusChangeOfAReplacedItemIsIgnored() {
        upNext.play(episode)
        let stale = AVPlayerItem(url: URL(string: "https://cdn.invalid/old.mp3")!)
        player.itemStatusChanged(.readyToPlay, duration: 1_234, of: ObjectIdentifier(stale))
        #expect(player.duration == 3_600)
        #expect(episode.duration == 3_600)

        player.itemStatusChanged(.failed, duration: .nan, of: ObjectIdentifier(stale))
        #expect(!player.didFail)
        #expect(player.wantsToPlay)
    }

    @Test func aPlayedEpisodeLeavesRemovePlaylistsWhenTheNextOneStarts() throws {
        let other = Episode(guid: "2", title: "F", publishedAt: .distantPast, audioURL: URL(string: "https://cdn.invalid/2.mp3")!)
        container.mainContext.insert(other)
        let playlists = PlaylistService(context: container.mainContext)
        let list = try playlists.createPlaylist(name: "L", colorKey: "blue", symbolName: "star")
        try playlists.add(episode, to: list)
        try playlists.add(other, to: list)

        upNext.play(episode)
        player.markPlayed(episode)
        #expect(list.entries?.count == 2, "still in the player")

        upNext.play(other)
        #expect(list.sortedEntries.compactMap(\.episode) == [other])
    }

    // MARK: Speed (N25) and settings

    @Test func settingsAreStoredAndRead() {
        #expect(player.globalSpeed == 1)
        #expect(player.skipBackwardInterval == 15 && player.skipForwardInterval == 30)
        #expect(!player.remoteSkipsChapters)
        player.globalSpeed = 1.47
        player.skipForwardInterval = 45
        player.skipBackwardInterval = 10
        player.remoteSkipsChapters = true

        let again = PlayerController(library: library, settings: settings)
        #expect(again.globalSpeed == 1.5)
        #expect(again.skipForwardInterval == 45 && again.skipBackwardInterval == 10)
        #expect(again.remoteSkipsChapters)
    }

    @Test func changingTheSpeedChangesThePodcastsOwnSpeedOrTheGlobalOne() throws {
        let podcast = try insertPodcast(for: episode)
        upNext.play(episode)
        player.setSpeed(1.3)
        #expect(player.globalSpeed == 1.3 && podcast.playbackSpeed == nil)
        #expect(player.speed == 1.3)

        player.setUsesPodcastSpeed(true)
        #expect(podcast.playbackSpeed == 1.3, "the podcast takes over the current speed")
        player.setSpeed(2)
        #expect(podcast.playbackSpeed == 2 && player.globalSpeed == 1.3)
        #expect(player.speed == 2)
        #expect(abs(player.avPlayerDefaultRate - 2) < 0.001)

        player.setUsesPodcastSpeed(false)
        #expect(podcast.playbackSpeed == nil)
        #expect(player.speed == 1.3)
        #expect(abs(player.avPlayerDefaultRate - 1.3) < 0.001)
    }

    @Test func ownSpeedFromThePodcastSettingsAppliesToThePlayingEpisode() throws {
        let podcast = try insertPodcast(for: episode)
        upNext.play(episode)
        player.setSpeed(1.5, for: podcast)
        #expect(abs(player.avPlayerDefaultRate - 1.5) < 0.001)
        player.setSpeed(nil, for: podcast)
        #expect(abs(player.avPlayerDefaultRate - 1) < 0.001, "back to the global speed")
    }

    // MARK: Outro (N28)

    @Test func playingAcrossTheOutroEndsTheEpisode() throws {
        let podcast = try insertPodcast(for: episode)
        try library.setSkipOutro(60, for: podcast)
        upNext.play(episode)
        player.currentItemBecameReady()
        player.seek(to: 3_539)
        player.timeChanged(3_539.6)
        #expect(player.episode == episode)
        player.timeChanged(3_540.1)
        #expect(episode.isPlayed && episode.playbackPosition == 0, "ends like a real end")
        #expect(player.episode == nil, "nothing else in Up Next")
    }

    /// A tick queued before a seek still carries the old time; it must not count as playing
    /// across the outro mark (N28).
    @Test func aStaleTickAfterSkippingBackDoesNotEndTheEpisode() throws {
        let podcast = try insertPodcast(for: episode)
        try library.setSkipOutro(60, for: podcast)
        upNext.play(episode)
        player.currentItemBecameReady()
        player.seek(to: 3_542)
        player.timeChanged(3_542)
        player.seek(to: 3_537)       // skip back 5 s
        player.timeChanged(3_541.9)  // stale: queued before the seek
        player.timeChanged(3_537.5)
        #expect(player.episode == episode)
        #expect(!episode.isPlayed)
    }

    @Test func seekingIntoTheOutroPlaysIt() throws {
        let podcast = try insertPodcast(for: episode)
        try library.setSkipOutro(60, for: podcast)
        upNext.play(episode)
        player.currentItemBecameReady()
        player.seek(to: 3_550)
        player.timeChanged(3_550.5)
        player.timeChanged(3_551)
        #expect(player.episode == episode)
        #expect(!episode.isPlayed)
    }

    // MARK: Sleep timer (A27, N27)

    @Test func sleepTimerPausesAfterItsPlayingTime() {
        upNext.play(episode)
        player.currentItemBecameReady()
        player.setSleepTimer(.duration(2))
        for tick in 1...3 { player.timeChanged(Double(tick) * 0.5) }
        #expect(player.wantsToPlay)
        #expect(player.outputVolume < 1, "fading out")
        player.timeChanged(2)
        #expect(!player.wantsToPlay)
        #expect(player.sleepTimer == nil, "fires once")
        #expect(player.outputVolume == 1)
    }

    @Test func sleepTimerAtTheEndOfTheEpisodeCuesTheNextOne() throws {
        let next = Episode(guid: "2", title: "F", publishedAt: .distantPast, audioURL: URL(string: "https://cdn.invalid/2.mp3")!)
        container.mainContext.insert(next)
        upNext.play(episode)
        upNext.playNext(next)
        player.setSleepTimer(.endOfEpisode)
        player.currentItemDidEnd()
        #expect(episode.isPlayed)
        #expect(player.episode == next)
        #expect(!player.wantsToPlay, "cued, not playing (N27)")
        #expect(player.sleepTimer == nil)
    }

    @Test func anEndOfChapterTimerFollowsTheNextEpisode() throws {
        let next = Episode(guid: "2", title: "F", publishedAt: .distantPast, audioURL: URL(string: "https://cdn.invalid/2.mp3")!)
        next.duration = 3_600
        next.playbackPosition = 1_500
        container.mainContext.insert(next)
        upNext.play(episode)
        upNext.playNext(next)
        player.currentItemBecameReady()
        player.setSleepTimer(.endOfChapter)
        #expect(player.sleepTimer?.chapterEnd == nil, "no chapters: ends with the episode")
        giveChapters()
        player.chaptersDidChange()
        #expect(player.sleepTimer?.chapterEnd == 600)

        upNext.skip()
        #expect(player.episode == next)
        #expect(player.sleepTimer?.chapterEnd == nil, "the next episode has no chapters (yet)")
        player.currentItemBecameReady()
        player.timeChanged(1_500.5)
        #expect(player.wantsToPlay, "the old chapter end must not pause the next episode")
    }

    @Test func cancellingTheSleepTimerRestoresTheVolume() {
        upNext.play(episode)
        player.currentItemBecameReady()
        player.setSleepTimer(.duration(5))
        player.timeChanged(0.5)
        #expect(player.outputVolume < 1)
        player.setSleepTimer(nil)
        #expect(player.sleepTimer == nil)
        #expect(player.outputVolume == 1)
    }

    // MARK: Chapters (concept §4.6, N26)

    private static let image = URL(string: "https://example.com/b.jpg")!

    private func giveChapters() {
        episode.chapters = ChapterSelection.normalized([
            Chapter(start: 0, title: "A"),
            Chapter(start: 600, title: "B", imageURL: Self.image),
            Chapter(start: 1_200, title: "C"),
        ], duration: 3_600)
        episode.chaptersSource = .podlove
    }

    @Test func theCurrentChapterFollowsPlaybackAndSeeking() {
        giveChapters()
        upNext.play(episode)
        player.currentItemBecameReady()
        player.timeChanged(10)
        #expect(player.chapterContext.chapter?.title == "A")
        player.seek(to: 650)
        #expect(player.chapterContext.chapter?.title == "B")
        #expect(player.chapterContext.imageURL == Self.image)
        player.timeChanged(650.5)
        player.timeChanged(1_200.2)
        #expect(player.chapterContext.index == 2)
    }

    @Test func skippingByChapter() {
        giveChapters()
        upNext.play(episode)
        player.currentItemBecameReady()
        player.seek(to: 650)
        player.nextChapter()
        #expect(player.currentTime == 1_200)
        player.nextChapter()
        #expect(player.currentTime == 1_200, "the last chapter has no next one")
        player.timeChanged(1_201)
        player.previousChapter()
        #expect(player.currentTime == 600, "just inside a chapter: back to the previous one")
        player.seek(to: 700)
        player.previousChapter()
        #expect(player.currentTime == 600, "further inside: back to its start")
    }

    @Test func sleepTimerPausesAtTheEndOfTheChapter() {
        giveChapters()
        upNext.play(episode)
        player.currentItemBecameReady()
        player.seek(to: 1_190)
        player.setSleepTimer(.endOfChapter)
        #expect(player.sleepTimer?.chapterEnd == 1_200)
        player.seek(to: 100)
        #expect(player.sleepTimer?.chapterEnd == 600, "a seek moves the timer to the new chapter's end")
        player.seek(to: 1_199.5)
        player.timeChanged(1_200.1)
        #expect(!player.wantsToPlay)
        #expect(player.sleepTimer == nil)
    }

    @Test func markingThePlayingEpisodePlayedShowsTheFirstChapter() {
        giveChapters()
        upNext.play(episode)
        player.currentItemBecameReady()
        player.seek(to: 650)
        player.markPlayed(episode)
        #expect(player.chapterContext.chapter?.title == "A")
    }

    @Test func remoteSkipButtonsJumpByChapterOnlyWhenSetAndAvailable() {
        let center = MPRemoteCommandCenter.shared()
        upNext.play(episode)
        player.remoteSkipsChapters = true
        #expect(center.skipForwardCommand.isEnabled, "no chapters: seconds")

        giveChapters()
        player.chaptersDidChange()
        #expect(!center.skipForwardCommand.isEnabled)
        #expect(center.nextTrackCommand.isEnabled && center.previousTrackCommand.isEnabled)

        player.remoteSkipsChapters = false
        #expect(center.skipForwardCommand.isEnabled && center.skipBackwardCommand.isEnabled)
    }

    /// AirPods (double and triple press) and some car stereos send next/previous track, never
    /// skip: those commands stay on and follow the same setting as the skip buttons.
    @Test func headphoneNextAndPreviousFollowTheSkipSetting() {
        let center = MPRemoteCommandCenter.shared()
        giveChapters()
        upNext.play(episode)
        player.currentItemBecameReady()
        player.skipForwardInterval = 30
        player.skipBackwardInterval = 15
        player.seek(to: 650)

        player.remoteSkipsChapters = false
        #expect(center.nextTrackCommand.isEnabled && center.previousTrackCommand.isEnabled)
        player.remoteNext()
        #expect(player.currentTime == 680)
        player.remotePrevious()
        #expect(player.currentTime == 665)

        player.remoteSkipsChapters = true
        #expect(center.nextTrackCommand.isEnabled && center.previousTrackCommand.isEnabled)
        player.remoteNext()
        #expect(player.currentTime == 1_200)
    }

    /// Every press pulses the matching button, by tap or from outside the app; playback that
    /// pauses or resumes on its own (interruption, Up Next) doesn't.
    @Test func pressesPulseTheMatchingButton() {
        giveChapters()
        upNext.play(episode)
        player.currentItemBecameReady()
        player.seek(to: 650)
        player.pause()
        player.resume()
        #expect(player.buttonPulses == PlayerButtonPulses())

        player.skipForward()
        player.togglePlayPause()
        #expect(player.buttonPulses.skipForward == 1)
        #expect(player.buttonPulses.playPause == 1)

        player.remoteSkipsChapters = false
        player.remoteNext()
        player.remotePrevious()
        player.remotePause()
        player.remoteResume()
        #expect(player.buttonPulses.skipForward == 2)
        #expect(player.buttonPulses.skipBackward == 1)
        #expect(player.buttonPulses.playPause == 3)

        player.remoteSkipsChapters = true
        player.remoteNext()
        player.remotePrevious()
        #expect(player.buttonPulses.nextChapter == 1)
        #expect(player.buttonPulses.previousChapter == 1)
        #expect(player.buttonPulses.skipForward == 2, "by chapter: the seconds button stays still")
    }

    @Test func playingFromAChapterStartsThere() throws {
        giveChapters()
        upNext.play(episode, at: 600)
        #expect(player.episode == episode)
        #expect(player.currentTime == 600)
        #expect(player.wantsToPlay)
    }

    private func insertPodcast(for episode: Episode) throws -> Podcast {
        let podcast = Podcast(feedURL: URL(string: "https://example.com/feed.xml")!, title: "P", subscribedAt: .distantPast)
        container.mainContext.insert(podcast)
        episode.podcast = podcast
        try container.mainContext.save()
        return podcast
    }

    /// The stored Up Next of the last session comes back paused.
    private func restoreAfterARestart() throws {
        container.mainContext.insert(QueueItem(nowPlaying: episode))
        try container.mainContext.save()
        upNext.restoreSession()
        #expect(player.episode == episode)
        #expect(!player.wantsToPlay)
    }
}
