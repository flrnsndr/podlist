import Foundation
import Observation
import SwiftData
import os

/// Downloads and their files (concept §4.7, ADR 0007): by hand, automatically for
/// playlists with auto-download (N31, N88), deleting played downloads (N32), pause (A39) and
/// the low-storage stop (N33). The only writer of `downloadState`, `localFileName` and the
/// real `fileSize`; the `Downloader` does the network work and reports back.
@MainActor @Observable
public final class DownloadService {
    /// Progress (0…1) of running downloads, by episode `uuid`; nil while the size is unknown.
    public private(set) var progress: [UUID: Double?] = [:]
    /// Why a download failed, since launch (A38).
    public private(set) var failures: [UUID: FeedFailureReason] = [:]
    public private(set) var isPaused: Bool
    /// Free bytes when last looked (each automatic check, the storage screen).
    public private(set) var availableCapacity: Int64?

    // MARK: Settings (stored in `UserDefaults`, A43)

    /// N32: downloads of played episodes are deleted once they leave the player.
    public var deletesPlayed: Bool {
        didSet { settings.set(deletesPlayed, forKey: SettingsKey.deletesPlayed) }
    }
    public var allowsCellular: Bool {
        didSet { settings.set(allowsCellular, forKey: SettingsKey.allowsCellular) }
    }
    /// Off: iOS Low Data Mode holds downloads back.
    public var allowsLowDataMode: Bool {
        didSet { settings.set(allowsLowDataMode, forKey: SettingsKey.allowsLowDataMode) }
    }

    public var isLowOnStorage: Bool { DownloadRules.isLowOnStorage(availableCapacity: availableCapacity) }

    /// The file of this episode is about to go; the player switches to the stream (A36).
    @ObservationIgnored var fileWillBeRemoved: ((Episode) -> Void)?

    private enum SettingsKey {
        static let deletesPlayed = "downloads.deletesPlayed"
        static let allowsCellular = "downloads.allowsCellular"
        static let allowsLowDataMode = "downloads.allowsLowDataMode"
        static let isPaused = "downloads.isPaused"
    }

    private let context: ModelContext
    @ObservationIgnored private let downloader: Downloader
    @ObservationIgnored private let files: DownloadFiles
    @ObservationIgnored private let settings: UserDefaults
    @ObservationIgnored private let capacity: @Sendable () -> Int64?
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    /// The one task loading each episode; events of any other task are stale.
    @ObservationIgnored private var tasks: [UUID: URLSessionTask] = [:]
    @ObservationIgnored private var flushWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    /// Skipped episodes (⏭) whose undo is still offered: their played download stays (A81).
    @ObservationIgnored private var keptForUndo: Set<UUID> = []

    public init(
        context: ModelContext, downloader: Downloader, files: DownloadFiles = .shared, settings: UserDefaults = .standard,
        availableCapacity: (@Sendable () -> Int64?)? = nil
    ) {
        self.context = context
        self.downloader = downloader
        self.files = files
        self.settings = settings
        self.capacity = availableCapacity ?? { files.availableCapacity() }
        settings.register(defaults: [
            SettingsKey.deletesPlayed: true, SettingsKey.allowsCellular: true,
            SettingsKey.allowsLowDataMode: false, SettingsKey.isPaused: false,
        ])
        deletesPlayed = settings.bool(forKey: SettingsKey.deletesPlayed)
        allowsCellular = settings.bool(forKey: SettingsKey.allowsCellular)
        allowsLowDataMode = settings.bool(forKey: SettingsKey.allowsLowDataMode)
        isPaused = settings.bool(forKey: SettingsKey.isPaused)
        eventTask = Task { [weak self, events = downloader.events] in
            for await event in events { self?.handle(event) }
        }
    }

    // MARK: Reading

    /// The downloaded file of the episode, if it is there.
    public func playableFileURL(for episode: Episode) -> URL? {
        guard episode.downloadState == .downloaded, let name = episode.localFileName, files.exists(fileNamed: name) else { return nil }
        return files.url(forFileNamed: name)
    }

    public func refreshCapacity() {
        availableCapacity = capacity()
    }

    // MARK: By hand

    /// Loads the episode (also "Erneut versuchen"); ignores the storage limit (N33). While
    /// paused it waits (A39).
    public func download(_ episode: Episode) {
        guard episode.downloadState != .downloaded, episode.downloadState != .downloading else { return }
        failures[episode.uuid] = nil
        episode.downloadState = .queued
        save()
        if !isPaused, tasks[episode.uuid] == nil { start(episode) }
    }

    /// Cancels or deletes the downloads, the file of a playing episode last (A36).
    public func delete(_ episodes: [Episode]) {
        for episode in episodes { removeDownload(of: episode) }
        save()
    }

    /// "Alle gespielten löschen" (concept §4.7); the episode in the player keeps its file.
    public func deleteAllPlayed() {
        let downloaded = (try? context.fetch(Self.withDownload)) ?? []
        delete(downloaded.filter { $0.isPlayed && !$0.isNowPlaying })
    }

    /// A39. The state changes at once; the running tasks hand over their resume data later
    /// (a "Fortsetzen" meanwhile simply starts them afresh).
    public func pause() async {
        isPaused = true
        settings.set(true, forKey: SettingsKey.isPaused)
        let running = tasks
        tasks = [:]
        progress = [:]
        for episode in (try? context.fetch(Self.withDownload)) ?? [] where episode.downloadState == .downloading {
            episode.downloadState = .queued
        }
        save()
        for (id, task) in running {
            guard let task = task as? URLSessionDownloadTask else { task.cancel(); continue }
            if let data = await task.cancelByProducingResumeData(), tasks[id] == nil { files.saveResumeData(data, for: id) }
        }
    }

    public func resume() {
        isPaused = false
        settings.set(false, forKey: SettingsKey.isPaused)
        for episode in (try? context.fetch(Self.withDownload)) ?? [] where episode.downloadState == .queued && tasks[episode.uuid] == nil {
            start(episode)
        }
        evaluate()
    }

    // MARK: Automatic

    /// Starts what the playlists with auto-download still need (N31), "Alles" included: it
    /// loads what it has, also of playlists without auto-download (N88). Called whenever
    /// entries, played states, the auto-download switch or the choice for "Alles" change.
    /// First, played downloads that are no longer wanted go (N32), e.g. one a keep playlist
    /// stopped keeping or one left over when the app ended during the undo of ⏭ (A81).
    public func evaluate() {
        refreshCapacity()
        deleteUnwantedPlayedDownloads()
        do {
            let playlists = try context.fetch(Playlist.allWithEntries())
            let loading = playlists.filter(\.autoDownload).sorted { $0.displayOrder < $1.displayOrder }
            // In each playlist's own order, so the episode it plays next loads first. A keep
            // playlist loads its played episodes too ("Alles" is never one, N99).
            let ordered = loading.flatMap { playlist in
                playlist.shownEpisodes(among: playlists).map { ($0, playlist.playedPolicy == .keep) }
            }
            let episodes = Dictionary(ordered.map { ($0.0.episodeID, $0.0) }, uniquingKeysWith: { first, _ in first })
            let candidates = ordered.map { episode, loadsPlayed in
                AutoDownloadEntry(
                    episode: episode.episodeID, isPlayed: episode.isPlayed, state: episode.downloadState, loadsPlayed: loadsPlayed)
            }
            let ids = DownloadRules.automaticDownloads(candidates, availableCapacity: availableCapacity, isPaused: isPaused)
            for id in ids {
                guard let episode = episodes[id] else { continue }
                episode.downloadState = .queued
                start(episode)
            }
            if !ids.isEmpty {
                save()
                Logger.downloads.info("Auto-download started \(ids.count) episodes")
            }
        } catch {
            Logger.downloads.error("Auto-download check failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// N32, A37: a played episode that left the player loses its download, unless a keep
    /// playlist that downloads automatically still has it. Returns whether it did.
    @discardableResult
    func deletePlayedDownloadIfNeeded(_ episode: Episode) -> Bool {
        let isKept = (episode.playlistEntries ?? []).contains { entry in
            entry.playlist.map { $0.playedPolicy == .keep && $0.autoDownload } ?? false
        }
        guard !keptForUndo.contains(episode.uuid), DownloadRules.shouldDeletePlayedDownload(
            isPlayed: episode.isPlayed, state: episode.downloadState, isNowPlaying: episode.isNowPlaying,
            deletesPlayed: deletesPlayed, isInKeepPlaylistWithAutoDownload: isKept) else { return false }
        removeDownload(of: episode)
        return true
    }

    private func deleteUnwantedPlayedDownloads() {
        guard deletesPlayed else { return }
        let downloaded = (try? context.fetch(Self.withDownload)) ?? []
        let deleted = downloaded.filter { $0.isPlayed && deletePlayedDownloadIfNeeded($0) }
        guard !deleted.isEmpty else { return }
        save()
        Logger.downloads.info("Deleted \(deleted.count) played downloads")
    }

    /// ⏭ can be undone (N101, A81): the episode keeps its file until `releaseKeptForUndo`.
    func keepForUndo(_ episode: Episode) {
        keptForUndo.insert(episode.uuid)
    }

    /// The undo is gone: a played episode that is not in the player loses its download now.
    func releaseKeptForUndo(_ episode: Episode) {
        guard keptForUndo.remove(episode.uuid) != nil else { return }
        deletePlayedDownloadIfNeeded(episode)
        save()
    }

    // MARK: After a launch

    /// Matches waiting downloads with the session, forgets files iOS or the user removed,
    /// then checks the playlists.
    public func restoreAfterLaunch() async {
        // Adopt the session's tasks the model still waits for; cancel the rest, all while paused.
        for (id, task) in await downloader.runningTasks() where tasks[id] == nil {
            let state = episode(id)?.downloadState
            if !isPaused, state == .queued || state == .downloading {
                tasks[id] = task
            } else {
                task.cancel()
            }
        }
        for episode in (try? context.fetch(Self.withDownload)) ?? [] {
            switch episode.downloadState {
            case .downloaded:
                if playableFileURL(for: episode) == nil {
                    Logger.downloads.notice("Download of \(episode.uuid, privacy: .public) is gone")
                    episode.downloadState = .none
                    episode.localFileName = nil
                }
            case .queued, .downloading:
                guard tasks[episode.uuid] == nil else { continue }
                if let name = files.existingFileName(for: episode.uuid) {
                    // Finished while the app was not running; its event may still come.
                    episode.downloadState = .downloaded
                    episode.localFileName = name
                    episode.fileSize = files.fileSize(ofFileNamed: name) ?? episode.fileSize
                    files.removeResumeData(for: episode.uuid)
                    continue
                }
                episode.downloadState = .queued
                if !isPaused { start(episode) }
            case .none, .failed:
                break
            }
        }
        save()
        evaluate()
    }

    /// For `.backgroundTask(.urlSession)`: returns once the session's events are handled
    /// and saved, so iOS may suspend the app afterwards.
    public func handleBackgroundEvents() async {
        await downloader.waitForBackgroundEvents()
        let token = UUID()
        await withCheckedContinuation { continuation in
            flushWaiters[token] = continuation
            downloader.flush(token)
        }
    }

    // MARK: Events

    private func handle(_ event: Downloader.Event) {
        switch event {
        case .progress(let id, let task, let written, let expected):
            guard let episode = episode(id), isCurrent(task, of: episode) else { return }
            if episode.downloadState == .queued {
                episode.downloadState = .downloading
                save()
            }
            let total = expected > 0 ? expected : (episode.fileSize ?? 0)
            progress.updateValue(total > 0 ? min(1, Double(written) / Double(total)) : nil, forKey: id)
        case .finished(let id, let task, let name, let bytes):
            // A finished file is never stale for a waiting episode: also while pausing, and also
            // from an older task whose cancel came too late (its file has the name the current
            // task would write; removing it could hit that task's file). The current task stops.
            guard let episode = episode(id), episode.downloadState == .queued || episode.downloadState == .downloading else {
                // Unwanted; the episode's own file has the same name, keep it.
                if episode(id)?.localFileName != name { files.remove(fileNamed: name) }
                return
            }
            if let current = tasks.removeValue(forKey: id), current.taskIdentifier != task { current.cancel() }
            progress[id] = nil
            files.removeResumeData(for: id)
            episode.downloadState = .downloaded
            episode.localFileName = name
            episode.fileSize = bytes
            save()
        case .failed(let id, let task, let reason, let resumeData):
            guard let episode = episode(id), isCurrent(task, of: episode) else { return }
            tasks[id] = nil
            progress[id] = nil
            if let resumeData { files.saveResumeData(resumeData, for: id) } else { files.removeResumeData(for: id) }
            episode.downloadState = .failed
            failures[id] = reason
            save()
        case .flushed(let token):
            flushWaiters.removeValue(forKey: token)?.resume()
        }
    }

    /// The event comes from the task loading this episode now. Without a known task (after
    /// a relaunch, before `restoreAfterLaunch`) any task of a waiting episode counts, but not
    /// while paused (the tasks being paused are stale).
    private func isCurrent(_ task: Int, of episode: Episode) -> Bool {
        guard episode.downloadState == .queued || episode.downloadState == .downloading else { return false }
        guard let current = tasks[episode.uuid] else { return !isPaused }
        return current.taskIdentifier == task
    }

    // MARK: Helpers

    private static var withDownload: FetchDescriptor<Episode> {
        let none = DownloadState.none.rawValue
        return FetchDescriptor(predicate: #Predicate { $0.downloadStateRaw != none })
    }

    private func start(_ episode: Episode) {
        tasks[episode.uuid]?.cancel()
        tasks[episode.uuid] = downloader.start(
            episode.uuid, from: episode.audioURL, resumeData: files.resumeData(for: episode.uuid),
            allowsCellular: allowsCellular, allowsLowDataMode: allowsLowDataMode)
    }

    /// Cancels a running download and deletes the file; does not save.
    private func removeDownload(of episode: Episode) {
        let id = episode.uuid
        let name = episode.localFileName
        episode.downloadState = .none
        episode.localFileName = nil
        progress[id] = nil
        failures[id] = nil
        files.removeResumeData(for: id)
        tasks.removeValue(forKey: id)?.cancel()
        if let name {
            fileWillBeRemoved?(episode)
            files.remove(fileNamed: name)
        }
    }

    private func episode(_ id: UUID) -> Episode? {
        var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func save() {
        do {
            try context.save()
        } catch {
            Logger.downloads.error("Saving downloads failed: \(String(describing: error), privacy: .public)")
        }
    }
}
