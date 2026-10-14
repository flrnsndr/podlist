import Foundation
import Observation
import SwiftData
import os

/// Up Next (concept §4.4, ADR 0004): every queue action builds a `QueueResolver` from the
/// stored state, runs one operation, writes state, cursors and history back and tells the
/// `PlayerController` what to play. The player reports back when an episode ends.
@MainActor @Observable
public final class UpNextService {
    /// The latest replacement or clearing, for the "Rückgängig" banner (concept §4.4).
    public struct UndoableChange: Hashable, Identifiable {
        /// The state before the change; restoring it undoes the change.
        public let snapshot: UpNextSnapshotValue
        /// The playlist that replaced Up Next; `nil` when it was cleared.
        public let playlist: PlaylistID?
        public var id: Date { snapshot.createdAt }
    }

    public private(set) var undoableChange: UndoableChange?

    private let context: ModelContext
    private let library: LibraryService
    private let player: PlayerController
    private let now: @Sendable () -> Date
    private var store: UpNextStore { UpNextStore(context: context) }

    public init(
        context: ModelContext, library: LibraryService, player: PlayerController,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.context = context
        self.library = library
        self.player = player
        self.now = now
        player.onEpisodeEnd = { [weak self] episode, playsOn in
            self?.episodeDidEnd(episode, playsOn: playsOn)
        }
    }

    // MARK: Reading

    /// Nothing is running and nothing is waiting (A7).
    public func isEmpty() -> Bool {
        (try? store.state().isEmpty) ?? true
    }

    /// Whether starting a playlist asks "Jetzt oder danach?" (concept §4.4, F13).
    public func startAction(preference: PlaylistStartPreference) -> PlaylistStartAction {
        QueueResolver.startAction(preference: preference, upNextIsEmpty: isEmpty())
    }

    /// The playlist's block is running (its episode is in the player).
    public func isRunning(_ playlist: Playlist) -> Bool {
        (try? store.state().nowPlaying?.playlist) == playlist.playlistID
    }

    /// The episodes a block will play, as the Up Next list shows them.
    public func upcomingEpisodes(of playlist: Playlist) -> [Episode] {
        do {
            let ids = try store.resolver().upcomingEpisodes(of: playlist.playlistID)
            let content = playlist.content(among: try context.fetch(FetchDescriptor<Playlist>()))
            return ids.compactMap(content.episode)
        } catch {
            Logger.upNext.error("Reading a block failed: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// `upcomingEpisodes(of:)` for many playlists with one resolver (the Playlists tab).
    public func upcomingEpisodes(of playlists: [Playlist]) -> [PlaylistID: [Episode]] {
        do {
            let resolver = try store.resolver()
            let all = try context.fetch(FetchDescriptor<Playlist>())
            return Dictionary(playlists.map { playlist in
                let content = playlist.content(among: all)
                return (playlist.playlistID, resolver.upcomingEpisodes(of: playlist.playlistID).compactMap(content.episode))
            }, uniquingKeysWith: { first, _ in first })
        } catch {
            Logger.upNext.error("Reading the blocks failed: \(String(describing: error), privacy: .public)")
            return [:]
        }
    }

    public func episode(_ id: EpisodeID) -> Episode? { try? store.episode(id) }
    public func playlist(_ id: PlaylistID) -> Playlist? { try? store.playlist(id) }

    // MARK: Playlists

    /// "Jetzt abspielen": replaces Up Next with the playlist, optionally from an episode
    /// ("Playlist ab hier"). The former state goes to the history and can be undone.
    public func playNow(_ playlist: Playlist, from episode: Episode? = nil) {
        let id = playlist.playlistID
        let recorded = perform(recordsHistory: true) { resolver, history, now in
            resolver.playNow(playlist: id, startingAt: episode?.episodeID, history: &history, now: now)
        }
        undoableChange = recorded.map { UndoableChange(snapshot: $0, playlist: id) }
    }

    /// "Am Ende anhängen" (scenario 4a).
    public func append(_ playlist: Playlist, from episode: Episode? = nil) {
        let id = playlist.playlistID
        perform { resolver, _, _ in resolver.append(playlist: id, startingAt: episode?.episodeID) }
    }

    /// "Nach der aktuellen Folge" (scenario 4c): the playlist comes right after the running
    /// episode; nothing is replaced, so nothing goes to the history (A54).
    public func playAfterCurrent(_ playlist: Playlist, from episode: Episode? = nil) {
        let id = playlist.playlistID
        perform { resolver, _, _ in resolver.playAfterCurrent(playlist: id, startingAt: episode?.episodeID) }
    }

    // MARK: Episodes

    /// "▶ Abspielen" (scenario 10); with `playlist` the ▶ of a row in that playlist, which
    /// jumps inside it if it is running (scenario 12). The loaded episode just resumes.
    /// Otherwise the episode's playlists follow the queue (N94).
    /// `time`: a chapter or a timestamp in the show notes was tapped (A30).
    public func play(_ episode: Episode, in playlist: Playlist? = nil, at time: TimeInterval? = nil) {
        if episode == player.episode {
            player.resume()
        } else {
            let id = episode.episodeID
            let playlistID = playlist?.playlistID
            perform { resolver, _, _ in
                let command = resolver.play(id, inPlaylist: playlistID)
                if resolver.state.nowPlaying?.playlist == nil { Self.playlistsFollow(episode, &resolver) }
                return command
            }
        }
        if let time, player.episode == episode { player.seek(to: time) }
    }

    /// "Als Nächstes" (scenario 2). The episode's playlists follow the queue (N94); if its
    /// running block plays it next anyway, it does not go into Up Next (N79, A79).
    public func playNext(_ episode: Episode) {
        let id = episode.episodeID
        episode.inboxHandled()
        perform { resolver, _, _ in
            guard resolver.state.nowPlaying?.episode != id else { return nil }
            let command = resolver.playNext(id)
            Self.playlistsFollow(episode, &resolver)
            return command
        }
    }

    /// "Am Ende" (scenario 3).
    public func playLast(_ episode: Episode) {
        let id = episode.episodeID
        episode.inboxHandled()
        perform { resolver, _, _ in resolver.playLast(id) }
    }

    /// Takes back "Als Nächstes" / "Am Ende" (undo in the inbox); a cued, paused episode
    /// leaves the player, a playing one plays on.
    public func withdraw(_ episode: Episode) {
        let id = episode.episodeID
        let isPlaying = player.isPlaying
        perform { resolver, _, _ in resolver.withdraw(id, isPlaying: isPlaying) }
    }

    // MARK: Editing Up Next

    /// Swiped away: a single episode or a block (the playlist keeps its cursor).
    public func remove(_ item: QueueItem) {
        guard let value = Self.value(of: item) else { return }
        perform { resolver, _, _ in resolver.remove(value); return nil }
    }

    /// The running episode swiped away: the next item takes its place (playing or paused,
    /// like the player was).
    public func removeNowPlaying() {
        let isPlaying = player.wantsToPlay
        perform { resolver, _, _ in resolver.removeNowPlaying(isPlaying: isPlaying) }
    }

    /// Reorders the waiting items (offsets as in the stored order, SwiftUI `onMove`). The
    /// playlists of dragged single episodes follow (N94); a dragged block changes none.
    public func moveItems(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        perform { resolver, _, _ in
            let moved = offsets.compactMap { index -> EpisodeID? in
                guard resolver.state.items.indices.contains(index), case .episode(let id) = resolver.state.items[index] else { return nil }
                return id
            }
            resolver.moveItems(fromOffsets: offsets, toOffset: destination)
            for id in moved {
                if let episode = try? store.episode(id) { Self.playlistsFollow(episode, &resolver) }
            }
            return nil
        }
    }

    /// "Warteschlange leeren" (scenario 7): the running episode plays on; can be undone.
    public func clear() {
        let recorded = perform(recordsHistory: true) { resolver, history, now in
            resolver.clear(history: &history, now: now)
            return nil
        }
        undoableChange = recorded.map { UndoableChange(snapshot: $0, playlist: nil) }
    }

    /// "Rückgängig" or a tap in "Vorherige Warteschlangen" (scenario 5). Restoring is
    /// itself recorded, so it can be undone too.
    public func restore(_ snapshot: UpNextSnapshotValue) {
        undoableChange = nil
        perform(recordsHistory: true, restartsLoadedEpisode: false) { resolver, history, now in
            resolver.restore(snapshot, history: &history, now: now)
        }
    }

    /// The banner went away; the change stays in the history.
    public func dismissUndo() {
        undoableChange = nil
    }

    // MARK: Player

    /// ⏭ (scenario 9).
    public func skip() {
        perform { resolver, _, _ in resolver.skip() }
    }

    /// After a launch: the episode that was running is back in the player, paused.
    public func restoreSession() {
        do {
            let state = try store.state()
            guard let current = state.nowPlaying, let episode = try store.episode(current.episode) else { return }
            player.cue(episode, at: library.startPosition(of: episode))
        } catch {
            Logger.upNext.error("Restoring Up Next failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The player reached the end of `episode` ("Folge E endet"): the successor is decided
    /// while the episode is still in its playlists, then it is marked played, the played
    /// policy removes it and the successor plays; with `playsOn: false` (sleep timer, N27)
    /// it is only cued.
    func episodeDidEnd(_ episode: Episode, playsOn: Bool = true) {
        perform(beforePlaying: { try self.library.episodeDidEnd(episode) }) { resolver, _, _ in
            guard resolver.state.nowPlaying?.episode == episode.episodeID else { return .stop }
            let command = resolver.episodeEnded()
            if !playsOn, case .play(let next) = command { return .cue(next) }
            return command
        }
    }

    // MARK: Plumbing

    /// Runs one resolver operation and carries out its result. Order matters: the player's
    /// progress is saved first, the new state is written before the player gets its command,
    /// and the played policy reaches an episode only after it left the player. Returns the
    /// snapshot the operation recorded in the history, if any.
    @discardableResult
    private func perform(
        recordsHistory: Bool = false,
        restartsLoadedEpisode: Bool = true,
        beforePlaying: () throws -> Void = {},
        _ operation: (inout QueueResolver, inout UpNextHistory, Date) -> PlaybackCommand?
    ) -> UpNextSnapshotValue? {
        player.saveProgress()
        do {
            var resolver = try store.resolver()
            var history = recordsHistory ? try store.history() : UpNextHistory()
            let previous = resolver.state.nowPlaying
            let latest = history.snapshots.first
            let command = operation(&resolver, &history, now())
            try store.write(resolver)
            if recordsHistory { try store.write(history) }
            try context.save()
            try beforePlaying()
            if let command {
                try execute(command, nowPlaying: resolver.state.nowPlaying, restartsLoadedEpisode: restartsLoadedEpisode)
            }
            if let previous, previous.episode != resolver.state.nowPlaying?.episode,
               let episode = try store.episode(previous.episode), episode.isPlayed {
                try library.applyPlayedPolicy(to: episode)
            }
            return history.snapshots.first == latest ? nil : history.snapshots.first
        } catch {
            Logger.upNext.error("Up Next operation failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// `restartsLoadedEpisode: false` (restoring): the episode that is already in the player
    /// stays as it is, playing or paused.
    private func execute(_ command: PlaybackCommand, nowPlaying: NowPlaying?, restartsLoadedEpisode: Bool) throws {
        switch command {
        case .play(let id), .cue(let id):
            guard let episode = try store.episode(id) else {
                player.stop()
                return
            }
            if !restartsLoadedEpisode, episode == player.episode { return }
            if case .play = command {
                episode.inboxHandled()  // starting is enough (N46)
            }
            if case .cue = command {
                player.cue(episode, at: library.startPosition(of: episode))
            } else {
                player.play(episode, at: try library.playbackWillStart(episode))
            }
        case .stop:
            if nowPlaying == nil { player.stop() } else { player.pause() }
        }
    }

    /// N94: the episode got its place in Up Next; it moves next to its neighbours there in
    /// each of its playlists ("Alles" has no order of its own). The only place where Up Next
    /// changes a playlist, and only its order; a sorted one becomes manual (N96).
    private static func playlistsFollow(_ episode: Episode, _ resolver: inout QueueResolver) {
        let playlists = (episode.playlistEntries ?? []).compactMap(\.playlist).tags
        let orders = resolver.episodeWasPlaced(episode.episodeID, in: playlists.map(\.playlistID))
        for playlist in playlists {
            guard let order = orders[playlist.playlistID], let index = order.firstIndex(of: episode.episodeID) else { continue }
            playlist.move(episode, to: index)
        }
    }

    private static func value(of item: QueueItem) -> UpNextItem? {
        if let episode = item.episode { return .episode(episode.episodeID) }
        if let playlist = item.playlist { return .playlist(playlist.playlistID) }
        return nil
    }
}

extension PlaylistStartPreference {
    /// N52: the setting moved to a new key in Slice 7, so every value stored before becomes
    /// the new default "Ersetzen" once.
    public static let storageKey = "playlistStartPreference.v2"

    public static func stored(in defaults: UserDefaults) -> PlaylistStartPreference {
        defaults.string(forKey: storageKey).flatMap(Self.init(rawValue:)) ?? .replace
    }
}
