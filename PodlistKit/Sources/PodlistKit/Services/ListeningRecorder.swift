import Foundation
import SwiftData
import os

/// Writes the listening log (concept §4.11, plan-hoerstatistik §4.2): the only writer of
/// `ListeningSession`. The `PlayerController` reports ticks, seeks and why playback stopped;
/// a `ListeningTally` counts, and the open session is stored once it is worth keeping, every
/// minute while it runs (as `interrupted`) and when it closes. Recording is always on (N56).
@MainActor
public final class ListeningRecorder {
    /// How often an open session is written while listening; a killed app loses at most this.
    static let writeInterval: TimeInterval = 60

    /// What a session stores about its episode, taken when it starts.
    private struct Snapshot {
        var episodeUUID: UUID
        var podcastUUID: UUID?
        var playlistUUID: UUID?
        var episodeTitle: String
        var podcastTitle: String
        var publishedAt: Date
        var duration: TimeInterval?
    }

    private let context: ModelContext
    private let now: @Sendable () -> Date
    private var tally: ListeningTally?
    private var snapshot: Snapshot?
    private var session: ListeningSession?
    private var lastWrite: Date?

    public init(context: ModelContext, now: @escaping @Sendable () -> Date = { Date() }) {
        self.context = context
        self.now = now
    }

    /// `episode` is playing and at `position`. The first tick opens a session; a tick of
    /// another episode closes the open one first.
    func tick(_ episode: Episode, position: TimeInterval) {
        let date = now()
        if let tally, tally.episode != episode.episodeID { stop(.switched) }
        guard var current = tally else {
            tally = ListeningTally(episode: episode.episodeID, at: date, position: position)
            snapshot = makeSnapshot(of: episode)
            return
        }
        current.tick(at: date, position: position)
        tally = current
        snapshot?.duration = episode.duration ?? snapshot?.duration
        guard current.isWorthKeeping else { return }
        if session == nil || lastWrite.map({ date.timeIntervalSince($0) >= Self.writeInterval }) == true {
            write(.interrupted)
            lastWrite = date
        }
    }

    /// The listener moved within `episode`; counts only while a session is open.
    func seek(_ episode: Episode, from: TimeInterval, to: TimeInterval) {
        guard tally?.episode == episode.episodeID else { return }
        tally?.seek(from: from, to: to)
    }

    /// Playback stopped: closes the open session (if it is worth keeping) with `reason`.
    func stop(_ reason: ListeningEndReason) {
        if tally?.isWorthKeeping == true { write(reason) }
        tally = nil
        snapshot = nil
        session = nil
        lastWrite = nil
    }

    // MARK: Writing

    private func makeSnapshot(of episode: Episode) -> Snapshot {
        Snapshot(
            episodeUUID: episode.uuid, podcastUUID: episode.podcast?.uuid, playlistUUID: playlist(of: episode),
            episodeTitle: episode.title, podcastTitle: episode.podcast?.title ?? "",
            publishedAt: episode.publishedAt, duration: episode.duration)
    }

    /// The playlist block the episode plays in (Up Next's now playing item).
    private func playlist(of episode: Episode) -> UUID? {
        let descriptor = FetchDescriptor<QueueItem>(predicate: #Predicate { $0.isNowPlaying })
        let item = try? context.fetch(descriptor).first
        guard item?.episode == episode else { return nil }
        return item?.playlist?.uuid
    }

    private func write(_ reason: ListeningEndReason) {
        guard let tally, let snapshot else { return }
        let session = self.session ?? {
            let session = ListeningSession(episodeUUID: snapshot.episodeUUID, startedAt: tally.startedAt)
            session.podcastUUID = snapshot.podcastUUID
            session.playlistUUID = snapshot.playlistUUID
            session.episodeTitle = snapshot.episodeTitle
            session.podcastTitle = snapshot.podcastTitle
            session.episodePublishedAt = snapshot.publishedAt
            session.startPosition = tally.startPosition
            context.insert(session)
            return session
        }()
        self.session = session
        session.endedAt = tally.endedAt
        session.endPosition = tally.endPosition
        session.listenedSeconds = tally.listenedSeconds
        session.contentSeconds = tally.contentSeconds
        session.skippedForwardSeconds = tally.skippedForwardSeconds
        session.skippedBackwardSeconds = tally.skippedBackwardSeconds
        session.episodeDuration = snapshot.duration
        session.endReason = reason
        do {
            try context.save()
        } catch {
            Logger.statistics.error("Saving a listening session failed: \(String(describing: error), privacy: .public)")
        }
    }
}
