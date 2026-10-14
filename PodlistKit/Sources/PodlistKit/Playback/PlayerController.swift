import AVFoundation
import Foundation
import MediaPlayer
import Observation
#if canImport(UIKit)
import UIKit
#endif
import os

/// The only owner of the `AVPlayer` (concept §6.5): streaming, audio session, lock screen
/// and remote commands, saving the listening position. `UpNextService` decides what plays
/// (`load`, `cue`, `stop`) and hears when an episode ends; all writes go through
/// `LibraryService`, `UpNextService` and, for the listening log, `ListeningRecorder`.
@MainActor @Observable
public final class PlayerController {
    public private(set) var episode: Episode?
    public private(set) var isPlaying = false
    public private(set) var isBuffering = false
    public private(set) var currentTime: TimeInterval = 0
    public private(set) var duration: TimeInterval?
    /// The current episode could not be loaded (offline, broken URL, …).
    public private(set) var didFail = false

    // MARK: Settings (stored in `UserDefaults`, concept §5)

    /// The speed for podcasts without their own (N25).
    public var globalSpeed: Double {
        didSet {
            settings.set(PlaybackRules.clampedSpeed(globalSpeed), forKey: SettingsKey.speed)
            applyRate()
        }
    }
    public var skipForwardInterval: TimeInterval {
        didSet {
            settings.set(skipForwardInterval, forKey: SettingsKey.skipForward)
            updateRemoteCommands()
        }
    }
    public var skipBackwardInterval: TimeInterval {
        didSet {
            settings.set(skipBackwardInterval, forKey: SettingsKey.skipBackward)
            updateRemoteCommands()
        }
    }
    /// N26: the skip buttons on the lock screen and headphones jump by chapter (if the
    /// episode has chapters) instead of by seconds.
    public var remoteSkipsChapters: Bool {
        didSet {
            settings.set(remoteSkipsChapters, forKey: SettingsKey.remoteSkipsChapters)
            updateRemoteCommands()
        }
    }

    /// Skip intervals the settings offer (A35); each has an SF Symbol (`gobackward.N`).
    public static let skipIntervals: [TimeInterval] = [5, 10, 15, 30, 45, 60, 75, 90]

    /// A running sleep timer (A27).
    public private(set) var sleepTimer: SleepTimer?
    /// The chapter at `currentTime`, its image and link (concept §4.6).
    public private(set) var chapterContext = ChapterContext()
    /// Presses per player button, in the app or from headphones, lock screen or car: the
    /// visible button pulses.
    public private(set) var buttonPulses = PlayerButtonPulses()

    /// Save the position at least this often while playing (concept §8).
    private static let saveInterval: TimeInterval = 5
    /// Ticks this close to a seek's target already come from after the seek.
    private static let seekTolerance: TimeInterval = 2

    /// Called when the episode played to its end (or reached its outro, N28), after the
    /// player let go of it. `playsOn` is false when a sleep timer stops with the episode (N27).
    @ObservationIgnored var onEpisodeEnd: ((_ episode: Episode, _ playsOn: Bool) -> Void)?

    private enum SettingsKey {
        static let speed = "player.speed"
        static let skipForward = "player.skipForward"
        static let skipBackward = "player.skipBackward"
        static let remoteSkipsChapters = "player.remoteSkipsChapters"
    }

    private let library: LibraryService
    @ObservationIgnored private let chapterService: ChapterService?
    @ObservationIgnored private let downloads: DownloadService?
    @ObservationIgnored private let recorder: ListeningRecorder?
    @ObservationIgnored private let settings: UserDefaults
    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var itemObservations: [NSKeyValueObservation] = []
    @ObservationIgnored private var notificationTokens: [any NSObjectProtocol] = []
    @ObservationIgnored private var lastSavedPosition: TimeInterval = 0
    @ObservationIgnored private var pendingStart: TimeInterval?
    /// A seek is under way: ticks far from its target were queued before it (stale).
    @ObservationIgnored private var seekTarget: TimeInterval?
    @ObservationIgnored private var seekGeneration = 0
    /// The user asked to play (the player may still be loading or buffering).
    @ObservationIgnored private(set) var wantsToPlay = false
    /// Playing was interrupted by the system (call, other app); resume if it allows.
    @ObservationIgnored private var resumeAfterInterruption = false
    @ObservationIgnored private var artwork: MPMediaItemArtwork?
    /// The image the lock screen shows or is loading: chapter image or episode artwork.
    @ObservationIgnored private var artworkURL: URL?

    /// `chapters` loads better chapters whenever an episode comes into the player (A29);
    /// `downloads` provides the files of downloaded episodes (concept §4.7); `recorder` keeps
    /// the listening log (concept §4.11).
    public init(
        library: LibraryService, chapters: ChapterService? = nil, downloads: DownloadService? = nil,
        settings: UserDefaults = .standard, recorder: ListeningRecorder? = nil
    ) {
        self.library = library
        self.chapterService = chapters
        self.downloads = downloads
        self.recorder = recorder
        self.settings = settings
        settings.register(defaults: [
            SettingsKey.speed: 1.0, SettingsKey.skipForward: 30.0, SettingsKey.skipBackward: 15.0,
            SettingsKey.remoteSkipsChapters: false,
        ])
        globalSpeed = PlaybackRules.clampedSpeed(settings.double(forKey: SettingsKey.speed))
        skipForwardInterval = settings.double(forKey: SettingsKey.skipForward)
        skipBackwardInterval = settings.double(forKey: SettingsKey.skipBackward)
        remoteSkipsChapters = settings.bool(forKey: SettingsKey.remoteSkipsChapters)
        observePlayer()
        observeAudioSession()
        setUpRemoteCommands()
        downloads?.fileWillBeRemoved = { [weak self] episode in self?.fileWillBeRemoved(of: episode) }
    }

    // MARK: Commands

    /// Loads and plays an episode from `start` (decided by `UpNextService`, which saved the
    /// progress of the previous one before changing Up Next). The episode that is already
    /// loaded just resumes.
    func play(_ episode: Episode, at start: TimeInterval) {
        if episode == self.episode, player.currentItem != nil, !didFail {
            resume()
            return
        }
        load(episode, at: start)
        resume()
    }

    /// Shows an episode paused at `position` without loading it yet (after a restart, or
    /// added to an empty Up Next). The first ▶ starts it like `load`.
    func cue(_ episode: Episode, at position: TimeInterval) {
        unload()
        self.episode = episode
        currentTime = position
        duration = episode.duration
        episodeDidChange()
        applyRate()
    }

    /// Nothing plays any more: the player is empty.
    func stop() {
        unload()
        episode = nil
        currentTime = 0
        duration = nil
        artwork = nil
        artworkURL = nil
        chapterContext = ChapterContext()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    public func togglePlayPause() {
        buttonPulses.playPause += 1
        isPlaying || wantsToPlay ? pause() : resume()
    }

    public func resume() {
        guard let episode else { return }
        if player.currentItem == nil || didFail {
            // After a restart or a failure: a manual start like `play(_:)` (N9).
            do {
                load(episode, at: try library.playbackWillStart(episode))
            } catch {
                Logger.playback.error("Starting playback failed: \(String(describing: error), privacy: .public)")
                return
            }
        }
        activateAudioSession()
        wantsToPlay = true
        if pendingStart == nil { player.play() }
        updateNowPlayingInfo()
    }

    public func pause() {
        recorder?.stop(.paused)
        wantsToPlay = false
        player.pause()
        saveProgress()
        updateNowPlayingInfo()
    }

    public func seek(to time: TimeInterval) {
        let upperBound = duration.map { max(0, $0 - 1) } ?? .greatestFiniteMagnitude
        let target = min(max(0, time), upperBound)
        if let episode { recorder?.seek(episode, from: currentTime, to: target) }
        currentTime = target
        updateChapterContext()
        if sleepTimer?.mode == .endOfChapter { sleepTimer?.chapterEnd = chapterContext.chapter?.end }
        if pendingStart != nil {
            pendingStart = target
        } else if player.currentItem != nil {
            seekTarget = target
            seekGeneration += 1
            let generation = seekGeneration
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600)) { @Sendable [weak self] _ in
                Task { @MainActor in self?.seekDidFinish(generation) }
            }
        } else if let episode {
            // Nothing loaded (restored after a restart): the next start begins here.
            do {
                try library.saveProgress(episode, position: target)
                lastSavedPosition = target
            } catch {
                Logger.playback.error("Saving progress failed: \(String(describing: error), privacy: .public)")
            }
        }
        saveProgress()
        updateNowPlayingInfo()
    }

    /// "Als gespielt markieren". For the episode in the player, the player's own position
    /// goes to 0 as well, so the next progress save cannot write the old position back (A8).
    public func markPlayed(_ episode: Episode) {
        do {
            if episode == self.episode {
                pause()
                currentTime = 0
                lastSavedPosition = 0
                if pendingStart != nil {
                    pendingStart = 0
                } else if player.currentItem != nil {
                    player.seek(to: .zero)
                }
                updateChapterContext()
                updateNowPlayingInfo()
            }
            try library.markPlayed(episode)
        } catch {
            Logger.playback.error("Marking played failed: \(String(describing: error), privacy: .public)")
        }
    }

    public func skipForward() {
        buttonPulses.skipForward += 1
        seek(to: currentTime + skipForwardInterval)
    }

    public func skipBackward() {
        buttonPulses.skipBackward += 1
        seek(to: currentTime - skipBackwardInterval)
    }

    // MARK: Speed (N25)

    /// The speed in effect: the podcast's own, else the global one.
    public var speed: Double {
        PlaybackRules.speed(podcast: episode?.podcast?.playbackSpeed, global: globalSpeed)
    }

    /// The current episode has chapters in the list (not only hidden ones).
    public var hasChapters: Bool { episode?.chapters.contains { !$0.isHidden } == true }

    /// The current podcast has its own speed.
    public var usesPodcastSpeed: Bool { episode?.podcast?.playbackSpeed != nil }

    /// Changes the speed in effect: the podcast's own if it has one, else the global one.
    public func setSpeed(_ value: Double) {
        let value = PlaybackRules.clampedSpeed(value)
        if let podcast = episode?.podcast, podcast.playbackSpeed != nil {
            do {
                try library.setPlaybackSpeed(value, for: podcast)
            } catch {
                Logger.playback.error("Saving the speed failed: \(String(describing: error), privacy: .public)")
            }
            applyRate()
        } else {
            globalSpeed = value
        }
    }

    /// "Nur für diesen Podcast": the podcast keeps the current speed as its own, or goes
    /// back to the global one.
    public func setUsesPodcastSpeed(_ isOn: Bool) {
        guard let podcast = episode?.podcast else { return }
        do {
            try library.setPlaybackSpeed(isOn ? speed : nil, for: podcast)
        } catch {
            Logger.playback.error("Saving the speed failed: \(String(describing: error), privacy: .public)")
        }
        applyRate()
    }

    /// The podcast's own speed from its settings (nil = global); applies right away if one
    /// of its episodes is in the player.
    public func setSpeed(_ speed: Double?, for podcast: Podcast) {
        do {
            try library.setPlaybackSpeed(speed, for: podcast)
        } catch {
            Logger.playback.error("Saving the speed failed: \(String(describing: error), privacy: .public)")
        }
        if episode?.podcast == podcast { applyRate() }
    }

    /// Internal for tests.
    var avPlayerDefaultRate: Double { Double(player.defaultRate) }

    private func applyRate() {
        let rate = Float(speed)
        player.defaultRate = rate
        if player.rate > 0 { player.rate = rate }
        updateNowPlayingInfo()
    }

    // MARK: Chapters (concept §4.6)

    /// The current episode's chapters, normalized for the measured duration.
    public var chapters: [Chapter] {
        ChapterSelection.normalized(episode?.chapters ?? [], duration: duration)
    }

    public func nextChapter() {
        buttonPulses.nextChapter += 1
        guard let start = ChapterSelection.nextStart(after: currentTime, in: chapters) else { return }
        seek(to: start)
    }

    public func previousChapter() {
        buttonPulses.previousChapter += 1
        seek(to: ChapterSelection.previousStart(before: currentTime, in: chapters))
    }

    /// Internal for tests: the episode's stored chapters changed (loaded by the `ChapterService`).
    func chaptersDidChange() {
        updateChapterContext()
        if sleepTimer?.mode == .endOfChapter { sleepTimer?.chapterEnd = chapterContext.chapter?.end }
        updateRemoteCommands()
    }

    /// A new episode is in the player: its chapters, artwork and remote commands.
    private func episodeDidChange() {
        artwork = nil
        artworkURL = nil
        seekTarget = nil
        chapterContext = ChapterSelection.context(at: currentTime, in: chapters)
        if sleepTimer?.mode == .endOfChapter { sleepTimer?.chapterEnd = chapterContext.chapter?.end }
        refreshArtwork()
        updateRemoteCommands()
        guard let chapterService, let episode else { return }
        Task {
            await chapterService.load(episode)
            guard self.episode == episode else { return }
            chaptersDidChange()
        }
    }

    private func updateChapterContext() {
        let context = ChapterSelection.context(at: currentTime, in: chapters)
        guard context != chapterContext else { return }
        chapterContext = context
        refreshArtwork()
        updateNowPlayingInfo()
    }

    // MARK: Sleep timer (A27, N27)

    /// Starts, replaces or (nil) cancels the sleep timer.
    public func setSleepTimer(_ mode: SleepTimer.Mode?) {
        sleepTimer = mode.map(SleepTimer.init)
        if mode == .endOfChapter { sleepTimer?.chapterEnd = chapterContext.chapter?.end }
        player.volume = 1
    }

    /// Wall-clock seconds until the sleep timer pauses; nil without a timer or estimate.
    public var sleepTimerSecondsLeft: TimeInterval? {
        sleepTimer?.secondsLeft(at: currentTime, rate: speed, episodeEnd: episodeEnd)
    }

    /// Internal for tests.
    var outputVolume: Float { player.volume }

    /// Where the episode ends: the outro mark (N28) or its duration.
    private var episodeEnd: TimeInterval? { outroStart ?? duration }

    private var outroStart: TimeInterval? {
        PlaybackRules.outroStart(duration: duration, skipOutro: TimeInterval(episode?.podcast?.skipOutroSeconds ?? 0))
    }

    private func advanceSleepTimer(from previous: TimeInterval, to current: TimeInterval) {
        guard var timer = sleepTimer, wantsToPlay else { return }
        timer.advance(by: (current - previous) / speed)
        if timer.isDue(at: current, rate: speed, episodeEnd: episodeEnd) {
            Logger.playback.info("Sleep timer paused playback")
            recorder?.stop(.sleepTimer)
            pause()
            setSleepTimer(nil)
            return
        }
        sleepTimer = timer
        player.volume = SleepTimer.volume(secondsLeft: timer.secondsLeft(at: current, rate: speed, episodeEnd: episodeEnd))
    }

    /// Saves the listening position (also called when the app goes to the background).
    public func saveProgress() {
        guard let episode, player.currentItem != nil, pendingStart == nil else { return }
        do {
            try library.saveProgress(episode, position: currentTime)
            lastSavedPosition = currentTime
        } catch {
            Logger.playback.error("Saving progress failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Loading

    /// The player lets go of its item; a session still open ends here (another episode or none).
    private func unload() {
        recorder?.stop(.switched)
        wantsToPlay = false
        pendingStart = nil
        didFail = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemObservations = []
    }

    private func load(_ episode: Episode, at start: TimeInterval) {
        self.episode = episode
        didFail = false
        currentTime = start
        lastSavedPosition = start
        duration = episode.duration
        pendingStart = start
        // A downloaded episode plays from its file, everything else streams (A36).
        let item = AVPlayerItem(url: downloads?.playableFileURL(for: episode) ?? episode.audioURL)
        item.audioTimePitchAlgorithm = .timeDomain
        observe(item)
        player.replaceCurrentItem(with: item)
        episodeDidChange()
        applyRate()
    }

    /// The URL the loaded item plays (internal for tests).
    var currentURL: URL? {
        (player.currentItem?.asset as? AVURLAsset)?.url
    }

    /// The file of `episode` is about to be deleted: if it plays from it, it goes on from
    /// the stream at the same place (A36).
    private func fileWillBeRemoved(of episode: Episode) {
        guard episode == self.episode, currentURL?.isFileURL == true else { return }
        let time = currentTime
        let playsOn = wantsToPlay
        load(episode, at: time)
        if playsOn { resume() }
    }

    private func observe(_ item: AVPlayerItem) {
        itemObservations = [
            item.observe(\.status) { @Sendable [weak self] item, _ in
                let status = item.status
                let duration = item.duration.seconds
                let itemID = ObjectIdentifier(item)
                Task { @MainActor in self?.itemStatusChanged(status, duration: duration, of: itemID) }
            },
        ]
    }

    /// Internal for tests. Ignores items that are no longer current (the callback hops to the
    /// main actor, so a quick switch to another episode can overtake it).
    func itemStatusChanged(_ status: AVPlayerItem.Status, duration itemDuration: TimeInterval, of itemID: ObjectIdentifier) {
        guard let current = player.currentItem, ObjectIdentifier(current) == itemID else { return }
        switch status {
        case .readyToPlay:
            if let episode, itemDuration.isFinite, itemDuration > 0 {
                duration = itemDuration
                try? library.updateDuration(episode, to: itemDuration)
            }
            guard let start = pendingStart else { return }
            if start > 0 {
                player.seek(to: CMTime(seconds: start, preferredTimescale: 600)) { @Sendable [weak self] _ in
                    Task { @MainActor in self?.finishPendingStart() }
                }
            } else {
                finishPendingStart()
            }
        case .failed:
            Logger.playback.error("Item failed: \(String(describing: self.player.currentItem?.error), privacy: .public)")
            recorder?.stop(.interrupted)
            didFail = true
            wantsToPlay = false
            pendingStart = nil
            player.replaceCurrentItem(with: nil)
        default:
            break
        }
    }

    /// The start position is reached: play if the user wants to.
    private func finishPendingStart() {
        guard pendingStart != nil else { return }
        pendingStart = nil
        if wantsToPlay { player.play() }
        updateNowPlayingInfo()
    }

    // MARK: Observation

    private func observePlayer() {
        observations = [
            // Changes arrive on AVFoundation's threads and their hops to the main actor can
            // overtake each other (a stale "paused" after "playing" left ▶ showing while an
            // episode played): read the current status on arrival instead of the reported one.
            player.observe(\.timeControlStatus) { @Sendable [weak self] _, _ in
                Task { @MainActor in self?.timeControlStatusChanged() }
            },
        ]
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { @Sendable [weak self] time in
            let seconds = time.seconds
            MainActor.assumeIsolated { self?.timeChanged(seconds) }
        }
        notificationTokens.append(NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main
        ) { @Sendable [weak self] notification in
            let item = notification.object as? AVPlayerItem
            let itemID = item.map(ObjectIdentifier.init)
            MainActor.assumeIsolated { self?.itemDidEnd(itemID) }
        })
    }

    private func timeControlStatusChanged() {
        let status = player.timeControlStatus
        isPlaying = status == .playing
        isBuffering = status == .waitingToPlayAtSpecifiedRate
    }

    private func seekDidFinish(_ generation: Int) {
        if generation == seekGeneration { seekTarget = nil }
    }

    /// Internal for tests: the periodic time observer reported `seconds`.
    func timeChanged(_ seconds: TimeInterval) {
        guard pendingStart == nil, seconds.isFinite, let item = player.currentItem else { return }
        if let seekTarget {
            // A tick from before the seek must not count as playing (outro, sleep timer).
            guard abs(seconds - seekTarget) <= Self.seekTolerance else { return }
            self.seekTarget = nil
        }
        let previous = currentTime
        currentTime = seconds
        if wantsToPlay, let episode { recorder?.tick(episode, position: seconds) }
        if let outroStart, PlaybackRules.reachesOutro(previous: previous, current: seconds, outroStart: outroStart) {
            itemDidEnd(ObjectIdentifier(item))
            return
        }
        if abs(seconds - lastSavedPosition) >= Self.saveInterval { saveProgress() }
        advanceSleepTimer(from: previous, to: seconds)
        updateChapterContext()
    }

    /// Internal for tests: the current item is ready and at its start position.
    func currentItemBecameReady() {
        finishPendingStart()
    }

    /// Internal for tests: the current item reached its end.
    func currentItemDidEnd() {
        itemDidEnd(player.currentItem.map(ObjectIdentifier.init))
    }

    /// The item played to its end. The player lets go of it first, so no later progress
    /// save writes the end position back; `UpNextService` then decides what comes next.
    private func itemDidEnd(_ itemID: ObjectIdentifier?) {
        guard let episode, let current = player.currentItem, itemID == ObjectIdentifier(current) else { return }
        recorder?.stop(.finished)
        unload()
        currentTime = 0
        let playsOn = sleepTimer?.endsWithEpisode != true
        if !playsOn { setSleepTimer(nil) }
        guard let onEpisodeEnd else {
            stop()
            return
        }
        onEpisodeEnd(episode, playsOn)
    }

    // MARK: Audio session

    // The audio session exists on iOS only; the package also builds for macOS so its tests
    // run without a simulator.
    private func activateAudioSession() {
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            try session.setActive(true)
        } catch {
            Logger.playback.error("Audio session failed: \(String(describing: error), privacy: .public)")
        }
        #endif
    }

    private func observeAudioSession() {
        #if os(iOS)
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { @Sendable [weak self] notification in
            let info = notification.userInfo
            let type = (info?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            let options = (info?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init)
            MainActor.assumeIsolated {
                guard let self else { return }
                switch type {
                case .began:
                    // The system paused us; a later tap on ▶ must play, not pause.
                    self.resumeAfterInterruption = self.wantsToPlay
                    self.recorder?.stop(.paused)
                    self.wantsToPlay = false
                    self.saveProgress()
                    self.updateNowPlayingInfo()
                case .ended:
                    if options?.contains(.shouldResume) == true, self.resumeAfterInterruption { self.resume() }
                    self.resumeAfterInterruption = false
                default:
                    break
                }
            }
        })
        notificationTokens.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { @Sendable [weak self] notification in
            let reason = (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt)
                .flatMap(AVAudioSession.RouteChangeReason.init)
            MainActor.assumeIsolated {
                // Headphones unplugged: pause instead of playing through the speaker.
                if reason == .oldDeviceUnavailable { self?.pause() }
            }
        })
        #endif
    }

    // MARK: Lock screen and remote commands

    private func setUpRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.remoteResume() }
            return .success
        }
        center.pauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.remotePause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        center.skipForwardCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.skipForward() }
            return .success
        }
        center.skipBackwardCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.skipBackward() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { @Sendable [weak self] event in
            guard let position = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime else {
                return .commandFailed
            }
            Task { @MainActor in self?.seek(to: position) }
            return .success
        }
        center.nextTrackCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.remoteNext() }
            return .success
        }
        center.previousTrackCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in self?.remotePrevious() }
            return .success
        }
        updateRemoteCommands()
    }

    private var remoteSkipsByChapter: Bool { remoteSkipsChapters && hasChapters }

    /// Next/previous track from headphones (AirPods double/triple press), the car or the lock
    /// screen in chapter mode: by chapter or by seconds, like the skip buttons (N26).
    func remoteNext() {
        if remoteSkipsByChapter { nextChapter() } else { skipForward() }
    }

    func remotePrevious() {
        if remoteSkipsByChapter { previousChapter() } else { skipBackward() }
    }

    /// Play and pause from outside count as a press of the play button; `resume()` and
    /// `pause()` themselves also run without a press (interruptions, Up Next).
    func remoteResume() {
        buttonPulses.playPause += 1
        resume()
    }

    func remotePause() {
        buttonPulses.playPause += 1
        pause()
    }

    /// Intervals follow the settings; with "Kapitel" (N26) and an episode with chapters the
    /// lock screen and headphones skip by chapter instead. Next/previous track stay enabled
    /// in both modes: AirPods only send those. The lock screen shows the skip buttons whenever
    /// they are enabled, so it still shows seconds in "Sekunden".
    private func updateRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForwardInterval)]
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBackwardInterval)]
        let byChapter = remoteSkipsByChapter
        center.skipForwardCommand.isEnabled = !byChapter
        center.skipBackwardCommand.isEnabled = !byChapter
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
    }

    private func updateNowPlayingInfo() {
        guard let episode else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: wantsToPlay ? speed : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: speed,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let podcast = episode.podcast {
            // A32: second line "Kapitel · Podcast".
            let chapter = chapterContext.chapter?.title ?? ""
            info[MPMediaItemPropertyArtist] = chapter.isEmpty ? podcast.title : [chapter, podcast.title].joined(separator: " · ")
            info[MPMediaItemPropertyAlbumTitle] = podcast.title
        }
        if let duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Loads the chapter image or the episode artwork for the lock screen when it changed.
    private func refreshArtwork() {
        guard let episode else { return }
        let url = chapterContext.imageURL ?? episode.imageURL ?? episode.podcast?.artworkURL
        guard url != artworkURL else { return }
        artworkURL = url
        guard let url else {
            artwork = nil
            updateNowPlayingInfo()
            return
        }
        #if canImport(UIKit)
        Task {
            guard let data = await ChapterImageStore.shared.imageData(for: url),
                  let image = UIImage(data: data) else { return }
            guard self.episode == episode, artworkURL == url else { return }
            artwork = Self.makeArtwork(image)
            updateNowPlayingInfo()
        }
        #endif
    }

    /// MediaPlayer calls the request handler on its own queue, so the closure must not
    /// inherit main-actor isolation (it would trap at runtime).
    #if canImport(UIKit)
    private nonisolated static func makeArtwork(_ image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }
    #endif
}

/// How often each player button was pressed, by tap or from headphones, lock screen or car.
/// Views pulse the visible button when its count changes (`symbolEffect(_:value:)`), so every
/// press, also one on the AirPods, gets the same visible feedback.
public struct PlayerButtonPulses: Equatable, Sendable {
    public internal(set) var playPause = 0
    public internal(set) var skipBackward = 0
    public internal(set) var skipForward = 0
    public internal(set) var previousChapter = 0
    public internal(set) var nextChapter = 0

    public init() {}
}
