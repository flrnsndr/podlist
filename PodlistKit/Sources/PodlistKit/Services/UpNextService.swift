import Foundation
import Observation
import SwiftData
import os

/// Up Next (concept §4.4, ADR 0008): every queue action builds a `QueueResolver` from the
/// stored state, runs one operation, writes state, resume points (N107) and history back
/// and tells the `PlayerController` what to play. The player reports back when an episode
/// ends. The queue never changes a playlist (N104).
@MainActor @Observable
public final class UpNextService {
    /// The latest replacement, clearing or ⏭, for the "Rückgängig" banner (concept §4.4, N101).
    public struct UndoableChange: Hashable, Identifiable {
        public enum Kind: Hashable {
            /// Up Next was replaced by this playlist.
            case replaced(PlaylistID)
            case cleared
            /// ⏭ skipped this episode as heard.
            case skipped(EpisodeID)
        }

        public let id = UUID()
        public let kind: Kind
        /// Up Next before the change; restoring it undoes a replacement or a clearing.
        public let snapshot: UpNextSnapshotValue
        /// The playlist that replaced Up Next; `nil` otherwise.
        public var playlist: PlaylistID? {
            if case .replaced(let id) = kind { id } else { nil }
        }
    }

    public private(set) var undoableChange: UndoableChange? {
        didSet {
            // Only the latest change can be undone: the download a skip kept may go now (A81).
            guard let skipped = skipUndo, skipped.change != undoableChange?.id else { return }
            skipUndo = nil
            if let episode = try? store.episode(skipped.episode) { library.releaseDownloadKeptForUndo(episode) }
        }
    }

    /// What undoing the latest ⏭ needs besides the queue state (A81).
    private struct SkipUndo {
        let change: UUID
        let episode: EpisodeID
        let before: LibraryService.ListeningState
        let wasPlaying: Bool
    }

    @ObservationIgnored private var skipUndo: SkipUndo?

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

    /// The running episode is one of the playlist's (N107: "Läuft").
    public func isRunning(_ playlist: Playlist) -> Bool {
        guard let resolver = try? store.resolver(), let current = resolver.state.nowPlaying else { return false }
        return resolver.playlists[playlist.playlistID]?.episodes.contains(current) ?? false
    }

    /// The playlist view's two parts (N106): its episodes in Up Next, in Up Next's order,
    /// and the rest in the playlist's sort. `playlists`: all playlists, fetched with
    /// `Playlist.allWithEntries` by the view.
    public func split(of playlist: Playlist, among playlists: [Playlist]) -> (live: [Episode], draft: [Episode]) {
        do {
            let resolver = try store.resolver(among: playlists)
            let episodes = store.episodesInPlaylists(playlists)
            let parts = resolver.split(of: playlist.playlistID)
            return (parts.live.compactMap { episodes[$0] }, parts.draft.compactMap { episodes[$0] })
        } catch {
            Logger.upNext.error("Reading the playlist's parts failed: \(String(describing: error), privacy: .public)")
            return ([], [])
        }
    }

    /// What the Playlists tab shows of the queue, from one resolver.
    public struct PlaylistsOverview {
        /// The episode each playlist continues with (N107): its frontmost one in Up Next,
        /// else its stored resume point, else its first episode; `nil` for an empty playlist.
        public var next: [PlaylistID: Episode] = [:]
        /// The playlists whose `next` is the running episode ("Läuft").
        public var running: Set<PlaylistID> = []
        /// The playlists whose `next` is waiting in Up Next ("Als Nächstes").
        public var queued: Set<PlaylistID> = []
        /// The playlists whose `next` is their stored resume point ("Weiter bei", N107).
        public var resumed: Set<PlaylistID> = []
        /// How many episodes "Alles" shows: its unplayed ones (N70).
        public var everythingCount = 0

        public init() {}
    }

    /// `playlists`: all playlists, as the tab lists them (fetched with `Playlist.allWithEntries`),
    /// so nothing is fetched again here.
    public func playlistsOverview(of playlists: [Playlist]) -> PlaylistsOverview {
        do {
            let resolver = try store.resolver(among: playlists)
            let episodes = store.episodesInPlaylists(playlists)
            var overview = PlaylistsOverview()
            for playlist in playlists {
                let id = playlist.playlistID
                if let queued = resolver.nextQueuedEpisode(of: id) {
                    overview.next[id] = episodes[queued]
                    if queued == resolver.state.nowPlaying { overview.running.insert(id) } else { overview.queued.insert(id) }
                } else if let resume = resolver.playlists[id]?.resumeEpisode {
                    overview.next[id] = episodes[resume]
                    overview.resumed.insert(id)
                } else if let next = resolver.takeover(of: id).first {
                    overview.next[id] = episodes[next]
                }
            }
            if let everything = playlists.everything, let queued = resolver.playlists[everything.playlistID] {
                overview.everythingCount = queued.episodes.count { !resolver.playedEpisodes.contains($0) }
            }
            return overview
        } catch {
            Logger.upNext.error("Reading the playlists failed: \(String(describing: error), privacy: .public)")
            return PlaylistsOverview()
        }
    }

    /// Where a waiting episode stands in Up Next, for moving it back (inbox undo, N105).
    public struct Place {
        /// The episode before it; `nil` = it is the front.
        public let predecessor: Episode?
    }

    /// The place of a waiting episode; `nil` when it is not waiting (running or not queued).
    public func place(of episode: Episode) -> Place? {
        guard let items = try? store.state().items, let index = items.firstIndex(of: episode.episodeID) else { return nil }
        guard index > 0 else { return Place(predecessor: nil) }
        return Place(predecessor: try? store.episode(items[index - 1]))
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
        undoableChange = recorded.map { UndoableChange(kind: .replaced(id), snapshot: $0) }
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

    /// "▶ Abspielen" (scenarios 10, 12): the episode plays now, the interrupted one comes back
    /// in front; a waiting episode moves to the front (N105). The loaded episode just resumes.
    /// `time`: a chapter or a timestamp in the show notes was tapped (A30).
    public func play(_ episode: Episode, at time: TimeInterval? = nil) {
        if episode == player.episode {
            player.resume()
        } else {
            let id = episode.episodeID
            perform { resolver, _, _ in resolver.play(id) }
        }
        if let time, player.episode == episode { player.seek(to: time) }
    }

    /// "Als Nächstes" (scenario 2, 2a): the episode moves right behind the running one (N105).
    public func playNext(_ episode: Episode) {
        let id = episode.episodeID
        episode.inboxHandled()
        perform { resolver, _, _ in resolver.playNext(id) }
    }

    /// "Am Ende" (scenario 3, 3a): the episode moves to the end (N105, A91).
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

    /// Swiped away in Up Next, or "Aus der Warteschlange" in a playlist view (scenario 17):
    /// the waiting episode leaves Up Next and stays in its playlists at its draft place.
    public func remove(_ episode: Episode) {
        let id = episode.episodeID
        perform { resolver, _, _ in resolver.remove(id); return nil }
    }

    /// The running episode swiped away: the next item takes its place (playing or paused,
    /// like the player was).
    public func removeNowPlaying() {
        let isPlaying = player.wantsToPlay
        perform { resolver, _, _ in resolver.removeNowPlaying(isPlaying: isPlaying) }
    }

    /// Reorders the waiting episodes (offsets as in the stored order, SwiftUI `onMove`).
    /// Changes no playlist (N104).
    public func moveItems(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        perform { resolver, _, _ in resolver.moveItems(fromOffsets: offsets, toOffset: destination); return nil }
    }

    /// Dragged in the live part of a playlist view (N106): the waiting episode goes right
    /// behind `predecessor` (the running episode or `nil`: to the front).
    public func move(_ episode: Episode, behind predecessor: Episode?) {
        let id = episode.episodeID
        let predecessorID = predecessor?.episodeID
        perform { resolver, _, _ in resolver.move(id, behind: predecessorID); return nil }
    }

    /// "Warteschlange leeren" (scenario 7): the running episode plays on; can be undone.
    public func clear() {
        let recorded = perform(recordsHistory: true) { resolver, history, now in
            resolver.clear(history: &history, now: now)
            return nil
        }
        undoableChange = recorded.map { UndoableChange(kind: .cleared, snapshot: $0) }
    }

    /// "Rückgängig" or a tap in "Vorherige Warteschlangen" (scenario 5). Restoring is
    /// itself recorded, so it can be undone too.
    public func restore(_ snapshot: UpNextSnapshotValue) {
        undoableChange = nil
        perform(recordsHistory: true, restartsLoadedEpisode: false) { resolver, history, now in
            resolver.restore(snapshot, history: &history, now: now)
        }
    }

    /// "Rückgängig" in the banner or by shaking: undoes the change if it is still the latest.
    public func undo(_ change: UndoableChange) {
        guard change.id == undoableChange?.id else { return }
        switch change.kind {
        case .replaced, .cleared: restore(change.snapshot)
        case .skipped: undoSkip(change)
        }
    }

    /// The banner went away; a replacement or clearing stays in the history.
    public func dismissUndo() {
        undoableChange = nil
    }

    // MARK: Player

    /// The episode ⏭ would play; `nil` disables ⏭ (N101).
    public func episodeAfterSkip() -> Episode? {
        do {
            return try store.resolver().episodeAfterSkip().flatMap { try store.episode($0) }
        } catch {
            Logger.upNext.error("Reading the next episode failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    /// ⏭ (scenario 9, N101): the running episode counts as heard, like at its end: the
    /// successor is decided first, then the episode is marked played (position 0) and the
    /// played policy applies once it left the player. It does not come back; "Rückgängig"
    /// takes all of it back (A81). Without a next episode nothing happens.
    public func skip() {
        player.saveProgress()
        guard let resolver = try? store.resolver(), let current = resolver.state.nowPlaying,
              resolver.episodeAfterSkip() != nil, let episode = try? store.episode(current) else { return }
        let before = library.listeningState(of: episode)
        let snapshot = UpNextSnapshotValue(createdAt: now(), reason: .restored, state: resolver.state)
        let wasPlaying = player.wantsToPlay
        library.keepDownloadForUndo(episode)
        perform(endsEpisode: true, beforePlaying: { try self.library.episodeDidEnd(episode) }) { resolver, _, _ in
            resolver.skip(isPlaying: wasPlaying)
        }
        let change = UndoableChange(kind: .skipped(current), snapshot: snapshot)
        undoableChange = change
        skipUndo = SkipUndo(change: change.id, episode: current, before: before, wasPlaying: wasPlaying)
    }

    /// Undo of ⏭ (A81): the episode gets back its played status, position and entries, and
    /// Up Next is restored with the episode in the player at its position, playing or paused
    /// as before. Setting Up Next back is recorded in the history, like every restore.
    private func undoSkip(_ change: UndoableChange) {
        guard let undo = skipUndo, undo.change == change.id else { return }
        defer { undoableChange = nil }  // last: the download is released once the episode is back
        do {
            guard let episode = try store.episode(undo.episode) else { return }
            player.saveProgress()
            try library.restore(undo.before, of: episode)
            perform(recordsHistory: true, startsAt: undo.before.position) { resolver, history, now in
                let command = resolver.restore(change.snapshot, history: &history, now: now)
                guard !undo.wasPlaying, case .play(let id) = command else { return command }
                return .cue(id)
            }
        } catch {
            Logger.upNext.error("Undoing ⏭ failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// After a launch: the episode that was running is back in the player, paused.
    public func restoreSession() {
        do {
            // The first read of a store from before ADR 0008 takes its blocks over (A90): saved here.
            let state = try store.state()
            if context.hasChanges { try context.save() }
            guard let current = state.nowPlaying, let episode = try store.episode(current) else { return }
            player.cue(episode, at: library.startPosition(of: episode))
        } catch {
            Logger.upNext.error("Restoring Up Next failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// The player reached the end of `episode` ("Folge E endet"): the next episode plays, the
    /// ended one is marked played and the played policy removes it from its playlists; with
    /// `playsOn: false` (sleep timer, N27) the next one is only cued.
    func episodeDidEnd(_ episode: Episode, playsOn: Bool = true) {
        perform(endsEpisode: true, beforePlaying: { try self.library.episodeDidEnd(episode) }) { resolver, _, _ in
            guard resolver.state.nowPlaying == episode.episodeID else { return .stop }
            let command = resolver.episodeEnded()
            if !playsOn, case .play(let next) = command { return .cue(next) }
            return command
        }
    }

    // MARK: Plumbing

    /// Runs one resolver operation and carries out its result. Order matters: the player's
    /// progress is saved first, the new state is written before the player gets its command,
    /// and the played policy reaches an episode only after it left the player. Returns the
    /// snapshot the operation recorded in the history, if any. `startsAt`: the episode of the
    /// command starts there instead of at its start position (undo of ⏭). `endsEpisode`: the
    /// running episode ends or is skipped, so a playlist it was the last of keeps no resume
    /// point (N107).
    @discardableResult
    private func perform(
        recordsHistory: Bool = false,
        restartsLoadedEpisode: Bool = true,
        startsAt position: TimeInterval? = nil,
        endsEpisode: Bool = false,
        beforePlaying: () throws -> Void = {},
        _ operation: (inout QueueResolver, inout UpNextHistory, Date) -> PlaybackCommand?
    ) -> UpNextSnapshotValue? {
        player.saveProgress()
        do {
            var resolver = try store.resolver()
            var history = recordsHistory ? try store.history() : UpNextHistory()
            let previous = resolver.state.nowPlaying
            let queuedBefore = store.queuedEpisodes(resolver)
            let latest = history.snapshots.first
            let command = operation(&resolver, &history, now())
            try store.write(resolver, before: queuedBefore, endsEpisode: endsEpisode)
            if recordsHistory { try store.write(history) }
            try context.save()
            try beforePlaying()
            if let command {
                try execute(
                    command, nowPlaying: resolver.state.nowPlaying, restartsLoadedEpisode: restartsLoadedEpisode, startsAt: position)
            }
            if let previous, previous != resolver.state.nowPlaying,
               let episode = try store.episode(previous), episode.isPlayed {
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
    private func execute(
        _ command: PlaybackCommand, nowPlaying: EpisodeID?, restartsLoadedEpisode: Bool, startsAt position: TimeInterval?
    ) throws {
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
            if let position {
                if case .cue = command { player.cue(episode, at: position) } else { player.play(episode, at: position) }
            } else if case .cue = command {
                player.cue(episode, at: library.startPosition(of: episode))
            } else {
                player.play(episode, at: try library.playbackWillStart(episode))
            }
        case .stop:
            if nowPlaying == nil { player.stop() } else { player.pause() }
        }
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
