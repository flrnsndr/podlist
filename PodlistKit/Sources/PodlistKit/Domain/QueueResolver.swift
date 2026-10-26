import Foundation

/// A playlist as the queue sees it: its episodes in the current display sort and its
/// stored resume point. The resolver only reads it (ADR 0008): it never changes which
/// episodes a playlist holds, their order, or its resume point.
public struct QueuePlaylist: Hashable, Sendable {
    public var id: PlaylistID
    public var playedPolicy: PlayedPolicy
    /// Already sorted (concept §4.2); the resolver does not sort.
    public var episodes: [EpisodeID]
    /// Wiedergabestand as stored: where the playlist continues when it is started again (N107).
    public var resumeEpisode: EpisodeID?

    public init(id: PlaylistID, playedPolicy: PlayedPolicy, episodes: [EpisodeID], resumeEpisode: EpisodeID?) {
        self.id = id
        self.playedPolicy = playedPolicy
        self.episodes = episodes
        self.resumeEpisode = resumeEpisode
    }
}

/// What the player has to do after a queue operation.
public enum PlaybackCommand: Hashable, Sendable {
    /// Load and play the episode at its stored position. An episode that was heard to the
    /// end has position 0 (the caller resets it), so it starts over (concept §4.3, N1).
    case play(EpisodeID)
    /// Load the episode paused at its stored position (something was added to an empty Up Next).
    case cue(EpisodeID)
    /// Stop playing. If Up Next still has a running episode (skipping without a next one),
    /// it stays loaded; otherwise the player is empty.
    case stop
}

/// Setting "Playlist starten" (concept §4.4, N43, A52): what a tap on ▶ does when Up Next
/// is not empty. A long press always offers all three ways.
public enum PlaylistStartPreference: String, Sendable, Codable, CaseIterable {
    /// Default: replace Up Next, with "Rückgängig".
    case replace
    /// Show the dialog with Ersetzen / Nach der aktuellen Folge / Ans Ende.
    case ask
}

public enum PlaylistStartAction: Hashable, Sendable {
    case askUser
    case playNow
}

/// The flat queue (concept §4.4 v0.7, ADR 0008): the running episode and the episodes
/// after it, each at most once. A playlist is taken over into it (`takeover`); afterwards
/// the queue and the playlist are independent. Pure logic on IDs.
///
/// Usage: build it from the persisted state, run one operation, write back `state`, then
/// execute the returned `PlaybackCommand`. After `episodeEnded()` the caller marks the
/// episode played and resets its position to 0; the played policy then removes it from its
/// playlists. Resume points (N107) are the store's business: it compares
/// `nextQueuedEpisode(of:)` before and after the operation.
public struct QueueResolver: Sendable {
    public private(set) var state: UpNextState
    public let playlists: [PlaylistID: QueuePlaylist]
    /// The playlists this resolver's operations took over (N107: the store clears their
    /// stored resume point; from now on it is derived from Up Next).
    public private(set) var takenOverPlaylists: Set<PlaylistID> = []
    public let playedEpisodes: Set<EpisodeID>

    public init(state: UpNextState, playlists: [QueuePlaylist], playedEpisodes: Set<EpisodeID>) {
        self.state = state
        self.playlists = Dictionary(playlists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.playedEpisodes = playedEpisodes
    }

    /// What a tap on ▶ does (N43, A52): replace at once, or ask when Up Next is not empty.
    public static func startAction(preference: PlaylistStartPreference, upNextIsEmpty: Bool) -> PlaylistStartAction {
        switch preference {
        case .replace: .playNow
        case .ask: upNextIsEmpty ? .playNow : .askUser
        }
    }

    // MARK: Taking a playlist over (N104)

    /// The episodes a playlist contributes when it is taken over, in the order they will
    /// play: from `episode` (tapped, "Playlist ab hier"), else from the playlist's frontmost
    /// episode in Up Next, else from its stored resume point, else from its first episode.
    /// A "remove" playlist goes round once (only unplayed episodes), a "keep" playlist plays
    /// to its end (heard episodes included, N1).
    public func takeover(of id: PlaylistID, startingAt episode: EpisodeID? = nil) -> [EpisodeID] {
        guard let playlist = playlists[id] else { return [] }
        let episodes = playlist.episodes
        let start = episode ?? nextQueuedEpisode(of: id) ?? playlist.resumeEpisode
        var order = episodes[...]
        if let start, let index = episodes.firstIndex(of: start) {
            order = episodes[index...] + (playlist.playedPolicy == .remove ? episodes[..<index] : [])
        }
        var seen: Set<EpisodeID> = []
        return order.filter { isPlayable($0, in: playlist) && seen.insert($0).inserted }
    }

    /// "Ersetzen" / "Playlist ab hier" (scenarios 1, 4b, 4e, 6, 11). The replaced state goes
    /// to the history. If the playlist's first episode is the running one, it stays running
    /// and nothing is reloaded (4e). Nothing to take over: nothing happens, no history entry.
    public mutating func playNow(
        playlist: PlaylistID, startingAt episode: EpisodeID? = nil, history: inout UpNextHistory, now: Date
    ) -> PlaybackCommand? {
        let order = takeover(of: playlist, startingAt: episode)
        guard let first = order.first else { return nil }
        takenOverPlaylists.insert(playlist)
        history.record(state, reason: .replaced, now: now)
        let keepsRunning = state.nowPlaying == first
        state = UpNextState(nowPlaying: first, items: Array(order.dropFirst()))
        return keepsRunning ? nil : .play(first)
    }

    /// "Nach der aktuellen Folge" (scenario 4c, A54): the playlist's episodes go right behind
    /// the running episode, in front of everything else; episodes already waiting move there
    /// (N105). Nothing is replaced, so nothing goes to the history. With nothing running it
    /// starts (A53).
    public mutating func playAfterCurrent(playlist: PlaylistID, startingAt episode: EpisodeID? = nil) -> PlaybackCommand? {
        let order = takeover(of: playlist, startingAt: episode).filter { $0 != state.nowPlaying }
        guard !order.isEmpty else { return nil }
        takenOverPlaylists.insert(playlist)
        let taken = Set(order)
        state.items = order + state.items.filter { !taken.contains($0) }
        return state.nowPlaying == nil ? activateFront() : nil
    }

    /// "Ans Ende" (scenario 4a, 4d): the playlist's episodes go to the end; episodes already
    /// waiting move there (N105). Starts playing if Up Next was empty.
    public mutating func append(playlist: PlaylistID, startingAt episode: EpisodeID? = nil) -> PlaybackCommand? {
        let order = takeover(of: playlist, startingAt: episode).filter { $0 != state.nowPlaying }
        guard !order.isEmpty else { return nil }
        takenOverPlaylists.insert(playlist)
        let taken = Set(order)
        state.items = state.items.filter { !taken.contains($0) } + order
        return state.nowPlaying == nil ? activateFront() : nil
    }

    // MARK: Single episodes (N105: an episode moves, it is never twice in Up Next)

    /// "▶ Abspielen" (scenarios 10, 12): the episode plays now; the interrupted episode comes
    /// back in front of Up Next (always, also a played one from a "keep" playlist).
    public mutating func play(_ episode: EpisodeID) -> PlaybackCommand {
        state.items.removeAll { $0 == episode }
        if let current = state.nowPlaying, current != episode {
            state.items.insert(current, at: 0)
        }
        state.nowPlaying = episode
        return .play(episode)
    }

    /// "Als Nächstes" (scenario 2, 2a). On an empty Up Next the episode is cued (A22).
    public mutating func playNext(_ episode: EpisodeID) -> PlaybackCommand? {
        guard state.nowPlaying != episode else { return nil }
        state.items.removeAll { $0 == episode }
        state.items.insert(episode, at: 0)
        return cueIfIdle()
    }

    /// "Am Ende" (scenario 3, 3a). On an empty Up Next the episode is cued (A22).
    public mutating func playLast(_ episode: EpisodeID) -> PlaybackCommand? {
        guard state.nowPlaying != episode else { return nil }
        state.items.removeAll { $0 == episode }
        state.items.append(episode)
        return cueIfIdle()
    }

    /// Takes back "Als Nächstes" / "Am Ende" (undo in the inbox): a waiting episode leaves
    /// Up Next. If it was cued on an empty Up Next (A22) and is still paused, it leaves the
    /// player, too (the next item is cued); once it plays, it plays on.
    public mutating func withdraw(_ episode: EpisodeID, isPlaying: Bool) -> PlaybackCommand? {
        if state.items.contains(episode) {
            state.items.removeAll { $0 == episode }
            return nil
        }
        guard !isPlaying, state.nowPlaying == episode else { return nil }
        state.nowPlaying = nil
        return cueIfIdle() ?? .stop
    }

    // MARK: Editing Up Next

    /// Swiped away in Up Next, or "Aus der Warteschlange" in a playlist view (scenario 17).
    /// The episode stays in its playlists at its draft place.
    public mutating func remove(_ episode: EpisodeID) {
        state.items.removeAll { $0 == episode }
    }

    /// The running episode swiped away in Up Next (N64): it stays unplayed and keeps its
    /// position. The next item plays, or is only cued if the player was paused; without one
    /// the player is empty.
    public mutating func removeNowPlaying(isPlaying: Bool) -> PlaybackCommand? {
        guard state.nowPlaying != nil else { return nil }
        state.nowPlaying = nil
        let command = activateFront()
        if !isPlaying, case .play(let next) = command { return .cue(next) }
        return command
    }

    /// Reorders the waiting episodes (SwiftUI `onMove` semantics). Never interrupts playback.
    public mutating func moveItems(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let moved = state.items.indices.filter { offsets.contains($0) }.map { state.items[$0] }
        let insertAt = destination - offsets.count { $0 < destination }
        state.items = state.items.indices.filter { !offsets.contains($0) }.map { state.items[$0] }
        state.items.insert(contentsOf: moved, at: min(max(0, insertAt), state.items.count))
    }

    /// Dragged in the live part of a playlist view (N106, scenario 16): the waiting episode
    /// goes right behind `predecessor`; behind the running episode (or to the front) when
    /// `predecessor` is the running one or `nil`. Episodes of other playlists in between stay
    /// where they are. Only for episodes that are waiting in Up Next.
    public mutating func move(_ episode: EpisodeID, behind predecessor: EpisodeID?) {
        guard state.items.contains(episode), predecessor != episode else { return }
        state.items.removeAll { $0 == episode }
        if let predecessor, let index = state.items.firstIndex(of: predecessor) {
            state.items.insert(episode, at: index + 1)
        } else {
            state.items.insert(episode, at: 0)
        }
    }

    // MARK: Playback events

    /// The running episode reached its end ("Folge E endet"): the next one plays. The caller
    /// then marks the ended episode played; the played policy takes it out of its playlists.
    public mutating func episodeEnded() -> PlaybackCommand {
        guard state.nowPlaying != nil else { return .stop }
        state.nowPlaying = nil
        return activateFront()
    }

    /// ⏭ (scenario 9, N101): the user skips the running episode on purpose, so it counts as
    /// heard; the caller marks it played. It does not come back. The next episode plays, or
    /// is only cued if the player was paused. Without a next episode (⏭ is disabled then)
    /// nothing changes: `nil`.
    public mutating func skip(isPlaying: Bool) -> PlaybackCommand? {
        var next = self
        guard state.nowPlaying != nil, case .play(let episode) = next.episodeEnded() else { return nil }
        self = next
        return isPlaying ? .play(episode) : .cue(episode)
    }

    /// The episode ⏭ would play now; `nil` if nothing follows (⏭ is disabled).
    public func episodeAfterSkip() -> EpisodeID? {
        state.nowPlaying == nil ? nil : state.items.first
    }

    // MARK: History

    /// "Warteschlange leeren" (scenario 7): the running episode keeps playing, playlists stay.
    public mutating func clear(history: inout UpNextHistory, now: Date) {
        guard !state.items.isEmpty else { return }
        history.record(state, reason: .cleared, now: now)
        state.items = []
    }

    /// Restores a former state ("Rückgängig", "Vorherige Warteschlangen"; scenario 5), as it
    /// was (A81). The current state goes to the history itself, so restoring can be undone too.
    public mutating func restore(_ snapshot: UpNextSnapshotValue, history: inout UpNextHistory, now: Date) -> PlaybackCommand? {
        history.record(state, reason: .restored, now: now)
        state = snapshot.state
        guard let current = state.nowPlaying else { return .stop }
        return .play(current)
    }

    // MARK: Derived for playlists (read only)

    /// The playlist's frontmost episode in Up Next, the running one included: its resume
    /// point while it is queued ("Läuft" / "Als Nächstes", N107). `nil` if none is queued.
    public func nextQueuedEpisode(of id: PlaylistID) -> EpisodeID? {
        guard let playlist = playlists[id] else { return nil }
        let members = Set(playlist.episodes)
        if let current = state.nowPlaying, members.contains(current) { return current }
        return state.items.first { members.contains($0) }
    }

    /// The playlist view's two parts (N106): `live` = its episodes that are in Up Next, in
    /// Up Next's order, the running one first; `draft` = the rest in the playlist's sort.
    public func split(of id: PlaylistID) -> (live: [EpisodeID], draft: [EpisodeID]) {
        guard let playlist = playlists[id] else { return ([], []) }
        let members = Set(playlist.episodes)
        let live = ([state.nowPlaying].compactMap { $0 } + state.items).filter { members.contains($0) }
        let queued = Set(live)
        return (live, playlist.episodes.filter { !queued.contains($0) })
    }

    // MARK: Plumbing

    private func isPlayable(_ episode: EpisodeID, in playlist: QueuePlaylist) -> Bool {
        playlist.playedPolicy == .keep || !playedEpisodes.contains(episode)
    }

    /// Makes the front item the running episode; with nothing waiting the player is empty.
    private mutating func activateFront() -> PlaybackCommand {
        guard !state.items.isEmpty else {
            state.nowPlaying = nil
            return .stop
        }
        let episode = state.items.removeFirst()
        state.nowPlaying = episode
        return .play(episode)
    }

    /// Nothing is running: the front item becomes the running episode, paused.
    private mutating func cueIfIdle() -> PlaybackCommand? {
        guard state.nowPlaying == nil else { return nil }
        guard case .play(let episode) = activateFront() else { return nil }
        return .cue(episode)
    }
}
