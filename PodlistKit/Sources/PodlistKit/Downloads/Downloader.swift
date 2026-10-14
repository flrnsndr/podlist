import Foundation
import Synchronization
import os

/// Loads episode files with a `URLSession` (ADR 0007): in the app a background session, so
/// downloads go on while the app is suspended; in tests an ephemeral one. Knows no models
/// and no rules: it starts, pauses and cancels, moves finished files into place and reports
/// what happened as `events`. The episode travels as its UUID in `taskDescription`, which
/// survives a relaunch; every event names its task, so the service can tell a stale task
/// (cancelled, replaced) from the current one.
public final class Downloader: NSObject, URLSessionDownloadDelegate, Sendable {
    public enum Event: Sendable {
        case progress(UUID, task: Int, written: Int64, expected: Int64)
        case finished(UUID, task: Int, fileName: String, bytes: Int64)
        /// `resumeData` lets a retry continue where it stopped.
        case failed(UUID, task: Int, FeedFailureReason, resumeData: Data?)
        /// Every event before this one has been delivered (`flush`).
        case flushed(UUID)
    }

    public static let backgroundIdentifier = "com.podlistapp.podlist.downloads"

    public let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let files: DownloadFiles
    private let state = Mutex(State())

    private struct State {
        var session: URLSession?
        /// `.backgroundTask(.urlSession)` waits here until the session has delivered its events.
        var backgroundWaiters: [CheckedContinuation<Void, Never>] = []
        var finishedBackgroundEvents = false
    }

    /// The app's downloader: a background session that also allows cellular and Low Data
    /// Mode; each request decides (`start`).
    public static func background(files: DownloadFiles = .shared) -> Downloader {
        let configuration = URLSessionConfiguration.background(withIdentifier: backgroundIdentifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        return Downloader(configuration: configuration, files: files)
    }

    public init(configuration: URLSessionConfiguration, files: DownloadFiles = .shared) {
        (events, continuation) = AsyncStream.makeStream()
        self.files = files
        super.init()
        configuration.allowsCellularAccess = true
        configuration.allowsConstrainedNetworkAccess = true
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        state.withLock { $0.session = session }
    }

    private var session: URLSession {
        state.withLock { $0.session! }
    }

    // MARK: Commands

    /// Starts a download and returns its task (cancel it directly, so a later task for the
    /// same episode is never hit). Resume data continues an earlier attempt, unless that
    /// attempt allowed more than the settings do now (A43).
    func start(_ episode: UUID, from url: URL, resumeData: Data?, allowsCellular: Bool, allowsLowDataMode: Bool) -> URLSessionDownloadTask {
        var task: URLSessionDownloadTask?
        if let resumeData {
            let resumed = session.downloadTask(withResumeData: resumeData)
            let old = resumed.originalRequest
            if (old?.allowsCellularAccess == true && !allowsCellular)
                || (old?.allowsConstrainedNetworkAccess == true && !allowsLowDataMode) {
                resumed.cancel()
            } else {
                task = resumed
            }
        }
        if task == nil {
            var request = URLRequest(url: url)
            request.allowsCellularAccess = allowsCellular
            request.allowsConstrainedNetworkAccess = allowsLowDataMode
            request.setValue("Podlist/1.0", forHTTPHeaderField: "User-Agent")
            task = session.downloadTask(with: request)
        }
        let started = task!
        started.taskDescription = episode.uuidString
        started.resume()
        return started
    }

    /// The tasks the session is still working on, by episode (after a relaunch).
    func runningTasks() async -> [UUID: URLSessionTask] {
        var result: [UUID: URLSessionTask] = [:]
        for task in await session.allTasks {
            guard let id = Self.episode(of: task) else { continue }
            if let other = result[id] {
                // Never two tasks for one episode.
                other.cancel()
            }
            result[id] = task
        }
        return result
    }

    /// Emits `.flushed(id)` after every event delivered so far.
    func flush(_ id: UUID) {
        continuation.yield(.flushed(id))
    }

    /// For `.backgroundTask(.urlSession)`: returns once the session has delivered the events
    /// it woke the app for.
    public func waitForBackgroundEvents() async {
        await withCheckedContinuation { continuation in
            let resumeNow = state.withLock { state in
                if state.finishedBackgroundEvents {
                    state.finishedBackgroundEvents = false
                    return true
                }
                state.backgroundWaiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    // MARK: URLSessionDownloadDelegate

    public func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard let id = Self.episode(of: downloadTask) else { return }
        continuation.yield(.progress(id, task: downloadTask.taskIdentifier, written: totalBytesWritten, expected: totalBytesExpectedToWrite))
    }

    /// The file must be moved before this returns; the system deletes it afterwards.
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let id = Self.episode(of: downloadTask) else { return }
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            continuation.yield(.failed(
                id, task: downloadTask.taskIdentifier, FeedFailureReason(FeedLoadError.http(status: http.statusCode)), resumeData: nil))
            return
        }
        let name = DownloadFiles.fileName(
            for: id, sourceURL: downloadTask.originalRequest?.url, mimeType: downloadTask.response?.mimeType)
        do {
            let bytes = try files.moveIntoPlace(location, named: name)
            continuation.yield(.finished(id, task: downloadTask.taskIdentifier, fileName: name, bytes: bytes))
        } catch {
            Logger.downloads.error("Moving the download failed: \(String(describing: error), privacy: .public)")
            continuation.yield(.failed(id, task: downloadTask.taskIdentifier, .other, resumeData: nil))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        guard let error, let id = Self.episode(of: task) else { return }
        // Cancelled on purpose (deleted or paused); the service already knows.
        if (error as? URLError)?.code == .cancelled { return }
        Logger.downloads.error("Download failed: \(String(describing: error), privacy: .public)")
        let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        continuation.yield(.failed(id, task: task.taskIdentifier, FeedFailureReason(error), resumeData: resumeData))
    }

    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let waiters = state.withLock { state in
            let waiters = state.backgroundWaiters
            state.backgroundWaiters = []
            state.finishedBackgroundEvents = waiters.isEmpty
            return waiters
        }
        waiters.forEach { $0.resume() }
    }

    private static func episode(of task: URLSessionTask) -> UUID? {
        task.taskDescription.flatMap(UUID.init(uuidString:))
    }
}
