import Foundation

/// A playlist as the queue sees it: its episodes in the current display sort and its
/// cursor. The resolver never changes which episodes it holds, only their order when an
/// episode gets its place in Up Next (N94).
public struct QueuePlaylist: Hashable, Sendable {
    public var id: PlaylistID
    public var playedPolicy: PlayedPolicy
    /// Already sorted (concept §4.2); the resolver does not sort.
    public var episodes: [EpisodeID]
    /// Wiedergabestand: the episode this playlist plays now or next.
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

/// Decides which episode plays next (concept §4.4). A playlist block works like a cursor
/// through its playlist; the cursor (`resumeEpisode`) belongs to the playlist.
///
/// Usage: build it from the persisted state, run one operation, write back `state` and the
/// playlists' `resumeEpisode`, then execute the returned `PlaybackCommand`. After
/// `episodeEnded()` the caller marks the episode played and resets its position to 0.
/// Whenever the played policy removes an episode (`PlayedRules.playlistsToRemoveFrom`, never
/// the running one), the caller first calls `playedEpisodeWillBeRemoved(_:from:)`; before an
/// episode is removed by hand, `episodeWillBeRemoved(_:from:)`.
public struct QueueResolver: Sendable {
    public private(set) var state: UpNextState
    public private(set) var playlists: [PlaylistID: QueuePlaylist]
    public private(set) var playedEpisodes: Set<EpisodeID>

    public init(state: UpNextState, playlists: [QueuePlaylist], playedEpisodes: Set<EpisodeID>) {
        self.state = state
        self.playlists = Dictionary(playlists.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        self.playedEpisodes = playedEpisodes
    }

    public static func startAction(preference: PlaylistStartPreference, upNextIsEmpty: Bool) -> PlaylistStartAction {
        if upNextIsEmpty { return .playNow }
        switch preference {
        case .replace: return .playNow
        case .ask: return .askUser
        }
    }

    // MARK: Playlists

    /// "Jetzt abspielen": replaces Up Next with the playlist (scenarios 1, 4b, 6, 11).
    /// The replaced state goes to the history; cursors and positions stay untouched.
    public mutating func playNow(
        playlist: PlaylistID, startingAt episode: EpisodeID? = nil, history: inout UpNextHistory, now: Date
    ) -> PlaybackCommand? {
        history.record(state, reason: .replaced, now: now)
        if let episode { moveCursor(of: playlist, to: episode) }
        state = UpNextState(items: [.playlist(playlist)])
        return activateFront()
    }

    /// "Am Ende anhängen" (scenario 4a). A playlist already in Up Next only moves to the end.
    /// Starts playing if Up Next was empty.
    public mutating func append(playlist: PlaylistID, startingAt episode: EpisodeID? = nil) -> PlaybackCommand? {
        let wasEmpty = state.isEmpty
        if let episode { moveCursor(of: playlist, to: episode) }
        state.items.removeAll { $0 == .playlist(playlist) }
        state.items.append(.playlist(playlist))
        return wasEmpty ? activateFront() : nil
    }

    /// "Nach der aktuellen Folge" (scenario 4c, A54): the block goes right behind the running
    /// episode, in front of everything else; a block already in Up Next moves there. Nothing
    /// is replaced, so nothing goes to the history. With nothing running it starts (A53, A61).
    /// "Playlist ab hier" on exactly the running episode makes it the block's episode; a
    /// block it came from moves on past it, as if it had ended there (A61).
    public mutating func playAfterCurrent(playlist: PlaylistID, startingAt episode: EpisodeID? = nil) -> PlaybackCommand? {
        guard playlists[playlist] != nil else { return nil }
        if let current = state.nowPlaying, let episode, episode == current.episode, current.playlist != playlist {
            advanceCursor(after: current)
            playlists[playlist]?.resumeEpisode = episode
            state.nowPlaying?.playlist = playlist
        } else if let episode {
            moveCursor(of: playlist, to: episode)
        }
        state.items.removeAll { $0 == .playlist(playlist) }
        state.items.insert(.playlist(playlist), at: 0)
        // Nothing runs although items wait: only reachable through an unusual restored
        // snapshot; the playlist starts like on an empty Up Next.
        return state.nowPlaying == nil ? activateFront() : nil
    }

    // MARK: Single episodes

    /// "Als Nächstes" (scenario 2). On an empty Up Next the episode is cued (A22).
    public mutating func playNext(_ episode: EpisodeID) -> PlaybackCommand? {
        guard state.nowPlaying?.episode != episode else { return nil }
        state.items.removeAll { $0 == .episode(episode) }
        state.items.insert(.episode(episode), at: 0)
        return cueIfIdle()
    }

    /// The episode just got its place in Up Next as a single episode or as the running one
    /// ("Als Nächstes", "Jetzt", dragged): it moves in each of `ids` next to its neighbours
    /// in Up Next (N94). Returns the playlists' new orders (only those that changed); the
    /// caller writes them. A single episode a block would now play at the same place leaves
    /// Up Next, so it does not play twice (A79, N79).
    @discardableResult
    public mutating func episodeWasPlaced(_ episode: EpisodeID, in ids: [PlaylistID]) -> [PlaylistID: [EpisodeID]] {
        var changed: [PlaylistID: [EpisodeID]] = [:]
        for id in ids {
            guard let playlist = playlists[id], let (queue, index) = placement(of: episode),
                  let order = QueuePlacement.order(
                    of: playlist.episodes, placing: episode, at: index, in: queue, resume: playlist.resumeEpisode)
            else { continue }
            playlists[id]?.episodes = order
            changed[id] = order
        }
        if let (queue, index) = placement(of: episode), state.nowPlaying?.episode != episode,
           queue.indices.contains(index + 1) && queue[index + 1] == episode || index > 0 && queue[index - 1] == episode {
            state.items.removeAll { $0 == .episode(episode) }
        }
        return changed
    }

    /// New episodes reached the playlist ("Alles", N98, A78, A80): its cursor moves to the
    /// first of them in its order that can play. If its block is running, the running
    /// episode plays on and the cursor waits ahead of it: the new episode comes next.
    public mutating func episodesArrived(_ episodes: Set<EpisodeID>, in id: PlaylistID) {
        guard let playlist = playlists[id],
              let first = playlist.episodes.first(where: { episodes.contains($0) && isPlayable($0, in: playlist) })
        else { return }
        playlists[id]?.resumeEpisode = first
    }

    /// Up Next as the episodes it will play (the running one, single episodes, the episodes
    /// of the blocks) and where the episode stands in it as the running or a single episode.
    private func placement(of episode: EpisodeID) -> (queue: [EpisodeID], index: Int)? {
        var queue: [EpisodeID] = []
        var index: Int?
        if let current = state.nowPlaying {
            if current.episode == episode, current.playlist == nil { index = 0 }
            queue.append(current.episode)
        }
        for item in state.items {
            switch item {
            case .episode(let id):
                if id == episode, index == nil { index = queue.count }
                queue.append(id)
            case .playlist(let id):
                queue += upcomingEpisodes(of: id)
            }
        }
        return index.map { (queue, $0) }
    }

    /// "Am Ende" (scenario 3). On an empty Up Next the episode is cued (A22).
    public mutating func playLast(_ episode: EpisodeID) -> PlaybackCommand? {
        guard state.nowPlaying?.episode != episode else { return nil }
        state.items.removeAll { $0 == .episode(episode) }
        state.items.append(.episode(episode))
        return cueIfIdle()
    }

    /// Takes back "Als Nächstes" / "Am Ende" (undo in the inbox): a waiting single episode
    /// leaves Up Next. If it was cued on an empty Up Next (A22) and is still paused, it leaves
    /// the player, too (the next item is cued); once it plays, it plays on.
    public mutating func withdraw(_ episode: EpisodeID, isPlaying: Bool) -> PlaybackCommand? {
        if state.items.contains(.episode(episode)) {
            state.items.removeAll { $0 == .episode(episode) }
            return nil
        }
        guard !isPlaying, state.nowPlaying == NowPlaying(episode: episode) else { return nil }
        state.nowPlaying = nil
        return cueIfIdle() ?? .stop
    }

    // MARK: Editing Up Next

    /// Swiped away in Up Next. A block only leaves Up Next: the playlist keeps its cursor,
    /// and an episode running from it plays to its end (the cursor still moves on then).
    public mutating func remove(_ item: UpNextItem) {
        state.items.removeAll { $0 == item }
    }

    /// The running episode swiped away in Up Next: like ⏭, but it does not come back. Its
    /// block's cursor moves on; it is not played and keeps its position. The next item plays,
    /// or is only cued if the player was paused; without one the player is empty.
    public mutating func removeNowPlaying(isPlaying: Bool) -> PlaybackCommand? {
        guard let current = state.nowPlaying else { return nil }
        advanceCursor(after: current)
        state.nowPlaying = nil
        let command = activateFront()
        if !isPlaying, case .play(let next) = command { return .cue(next) }
        return command
    }

    /// Reorders the waiting items (SwiftUI `onMove` semantics). Never interrupts playback.
    public mutating func moveItems(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let moved = state.items.indices.filter { offsets.contains($0) }.map { state.items[$0] }
        let insertAt = destination - offsets.count { $0 < destination }
        state.items = state.items.indices.filter { !offsets.contains($0) }.map { state.items[$0] }
        state.items.insert(contentsOf: moved, at: min(max(0, insertAt), state.items.count))
    }

    /// The playlist is about to be deleted: its block leaves Up Next, and an episode
    /// running from it plays on as a single episode.
    public mutating func playlistWillBeDeleted(_ id: PlaylistID) {
        state.items.removeAll { $0 == .playlist(id) }
        if state.nowPlaying?.playlist == id { state.nowPlaying?.playlist = nil }
        playlists[id] = nil
    }

    /// The episodes a block will play, in order, as Up Next shows them: from its cursor
    /// (or after the running episode) until it is done or, in a "remove" playlist, has
    /// gone round once. The running episode is not repeated.
    public func upcomingEpisodes(of id: PlaylistID) -> [EpisodeID] {
        guard let playlist = playlists[id] else { return [] }
        var preview = self
        var next: EpisodeID?
        if let current = state.nowPlaying, current.playlist == id {
            if playlist.playedPolicy == .remove { preview.playedEpisodes.insert(current.episode) }
            next = cursorIsAhead(of: current)
                ? preview.entryEpisode(of: playlist) : preview.successor(of: current.episode, in: playlist)
        } else {
            next = preview.entryEpisode(of: playlist)
        }
        var result: [EpisodeID] = []
        var seen: Set<EpisodeID> = []
        while let episode = next, seen.insert(episode).inserted {
            result.append(episode)
            next = preview.successor(of: episode, in: playlist)
        }
        return result
    }

    /// "▶ Abspielen" (scenario 10). With `inPlaylist` set to the running playlist, the
    /// ▶ of a playlist row jumps inside that playlist instead (scenario 12).
    public mutating func play(_ episode: EpisodeID, inPlaylist playlist: PlaylistID? = nil) -> PlaybackCommand {
        if let playlist, state.nowPlaying?.playlist == playlist, playlists[playlist] != nil {
            playlists[playlist]?.resumeEpisode = episode
            state.nowPlaying = NowPlaying(episode: episode, playlist: playlist)
            return start(episode)
        }
        interruptCurrent()
        state.items.removeAll { $0 == .episode(episode) }
        state.nowPlaying = NowPlaying(episode: episode)
        return start(episode)
    }

    // MARK: Playback events

    /// The running episode reached its end ("Folge E endet"). Determines the successor
    /// while the episode is still in its playlist; the caller then marks it played.
    public mutating func episodeEnded() -> PlaybackCommand {
        guard let current = state.nowPlaying else { return .stop }
        // It is about to be marked played: no other "remove" block may pick it again.
        playedEpisodes.insert(current.episode)
        advanceCursor(after: current)
        state.nowPlaying = nil
        return activateFront()
    }

    /// The played policy is about to remove a played episode from these playlists.
    /// Cursors pointing at it move on to its successor first, so a playlist never loses
    /// its place ("Nachfolger bestimmen, BEVOR die playedPolicy E aus p entfernt").
    public mutating func playedEpisodeWillBeRemoved(_ episode: EpisodeID, from ids: [PlaylistID]) {
        playedEpisodes.insert(episode)
        episodeWillBeRemoved(episode, from: ids)
    }

    /// An episode is about to be removed from these playlists by hand. As for the played
    /// policy, cursors pointing at it move on, so the playlist keeps its place (Florian,
    /// Slice 2). If it is running from one of them, it plays to its end as a single episode
    /// and the block continues after it (or is done, like a finished "keep" playlist).
    public mutating func episodeWillBeRemoved(_ episode: EpisodeID, from ids: [PlaylistID]) {
        for id in ids {
            guard let playlist = playlists[id], playlist.resumeEpisode == episode else { continue }
            let next = successor(of: episode, in: playlist)
            playlists[id]?.resumeEpisode = next
            guard state.nowPlaying == NowPlaying(episode: episode, playlist: id) else { continue }
            state.nowPlaying?.playlist = nil
            if next == nil { state.items.removeAll { $0 == .playlist(id) } }
        }
    }

    /// Several episodes leave a playlist at once ("Alles" after a playlist or podcast was
    /// left out or deleted, concept §4.1): its cursor moves past all of them, as for one.
    public mutating func episodesWillBeRemoved(_ episodes: Set<EpisodeID>, from id: PlaylistID) {
        guard let playlist = playlists[id], let cursor = playlist.resumeEpisode, episodes.contains(cursor) else { return }
        playlists[id]?.episodes.removeAll { $0 != cursor && episodes.contains($0) }
        episodeWillBeRemoved(cursor, from: [id])
        playlists[id]?.episodes = playlist.episodes
    }

    /// ⏭ (scenario 9): the next episode plays, the skipped one comes right after it.
    /// Without a next episode playback stops and Up Next stays as it is.
    public mutating func skip() -> PlaybackCommand {
        guard let current = state.nowPlaying else { return .stop }
        var next = self
        next.advanceCursor(after: current)
        next.state.nowPlaying = nil
        let command = next.activateFront()
        guard command != .stop else { return .stop }
        next.state.items.insert(.episode(current.episode), at: 0)
        self = next
        return command
    }

    // MARK: History

    /// "Warteschlange leeren" (scenario 7): the running episode keeps playing, playlists stay.
    public mutating func clear(history: inout UpNextHistory, now: Date) {
        guard !state.items.isEmpty else { return }
        history.record(state, reason: .cleared, now: now)
        state.items = []
    }

    /// Restores a former state ("Rückgängig", "Vorherige Warteschlangen"; scenario 5).
    /// The current state goes to the history itself, so restoring can be undone too.
    /// Cursors are never moved back: if the restored episode's playlist has moved on,
    /// the episode plays as a single episode.
    public mutating func restore(
        _ snapshot: UpNextSnapshotValue, history: inout UpNextHistory, now: Date
    ) -> PlaybackCommand? {
        history.record(state, reason: .restored, now: now)
        state = snapshot.state
        guard let current = state.nowPlaying else { return .stop }
        if let playlist = current.playlist, playlists[playlist]?.resumeEpisode != current.episode {
            state.nowPlaying?.playlist = nil
        }
        return start(current.episode)
    }

    // MARK: Cursor rules

    private func isPlayable(_ episode: EpisodeID, in playlist: QueuePlaylist) -> Bool {
        playlist.playedPolicy == .keep || !playedEpisodes.contains(episode)
    }

    /// "Block p wird aktiv": the cursor if it is still in p, otherwise the first episode.
    private func entryEpisode(of playlist: QueuePlaylist) -> EpisodeID? {
        if let resume = playlist.resumeEpisode {
            if playlist.episodes.contains(resume), isPlayable(resume, in: playlist) { return resume }
            return successor(of: resume, in: playlist)
        }
        return playlist.episodes.first { isPlayable($0, in: playlist) }
    }

    /// The episode after `episode` in the playlist's current sort. At the end a "remove"
    /// playlist starts over (only unplayed episodes are left), a "keep" playlist is done.
    /// If `episode` is no longer in the playlist, the playlist starts at its first episode.
    private func successor(of episode: EpisodeID, in playlist: QueuePlaylist) -> EpisodeID? {
        let candidates = { (slice: ArraySlice<EpisodeID>) in
            slice.first { $0 != episode && isPlayable($0, in: playlist) }
        }
        guard let index = playlist.episodes.firstIndex(of: episode) else {
            return candidates(playlist.episodes[...])
        }
        if let next = candidates(playlist.episodes[(index + 1)...]) { return next }
        switch playlist.playedPolicy {
        case .remove: return candidates(playlist.episodes[...])
        case .keep: return nil
        }
    }

    /// The block's cursor waits ahead of its running episode (`episodesArrived`) and would
    /// play another episode next; a waiting episode that can no longer play does not count.
    private func cursorIsAhead(of current: NowPlaying) -> Bool {
        guard let id = current.playlist, let playlist = playlists[id],
              let resume = playlist.resumeEpisode, resume != current.episode,
              let entry = entryEpisode(of: playlist) else { return false }
        return entry != current.episode
    }

    private mutating func advanceCursor(after current: NowPlaying) {
        guard let id = current.playlist, let playlist = playlists[id] else { return }
        if cursorIsAhead(of: current) { return }
        let next = successor(of: current.episode, in: playlist)
        playlists[id]?.resumeEpisode = next
        if next == nil { state.items.removeAll { $0 == .playlist(id) } }
    }

    /// Moves a playlist's cursor from outside ("Playlist ab hier"). If that playlist is
    /// running, the running episode continues as a single episode.
    private mutating func moveCursor(of id: PlaylistID, to episode: EpisodeID) {
        guard playlists[id] != nil else { return }
        playlists[id]?.resumeEpisode = episode
        if state.nowPlaying?.playlist == id, state.nowPlaying?.episode != episode {
            state.nowPlaying?.playlist = nil
        }
    }

    /// An interrupted episode goes back to the front unless its block will resume it.
    private mutating func interruptCurrent() {
        guard let current = state.nowPlaying else { return }
        let blockResumesIt = !cursorIsAhead(of: current) && current.playlist.map { state.items.contains(.playlist($0)) } ?? false
        if !blockResumesIt { state.items.insert(.episode(current.episode), at: 0) }
        state.nowPlaying = nil
    }

    /// Makes the front item play: a single episode leaves Up Next, a block stays and
    /// plays its entry episode. Empty or unknown blocks are dropped.
    private mutating func activateFront() -> PlaybackCommand {
        while let item = state.items.first {
            switch item {
            case .episode(let episode):
                state.items.removeFirst()
                state.nowPlaying = NowPlaying(episode: episode)
                return start(episode)
            case .playlist(let id):
                if let playlist = playlists[id], let episode = entryEpisode(of: playlist) {
                    playlists[id]?.resumeEpisode = episode
                    state.nowPlaying = NowPlaying(episode: episode, playlist: id)
                    return start(episode)
                }
                state.items.removeFirst()
            }
        }
        state.nowPlaying = nil
        return .stop
    }

    private func start(_ episode: EpisodeID) -> PlaybackCommand {
        .play(episode)
    }

    /// Nothing is running: the front item becomes the running episode, paused.
    private mutating func cueIfIdle() -> PlaybackCommand? {
        guard state.nowPlaying == nil else { return nil }
        guard case .play(let episode) = activateFront() else { return nil }
        return .cue(episode)
    }
}
