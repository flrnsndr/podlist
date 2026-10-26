import Foundation
import SwiftData
import os

/// Persistence of Up Next (ADR 0008): builds a `QueueResolver` from the stored `QueueItem`s
/// and all playlists, and writes its state, the playlists' resume points (N107) and the
/// history back. Does not save.
struct UpNextStore {
    let context: ModelContext

    // MARK: Resolver

    func resolver() throws -> QueueResolver {
        try resolver(among: try playlists())
    }

    /// All playlists with their entries prefetched (`Playlist.allWithEntries`): the resolver
    /// walks every entry, and every screen update builds one.
    func playlists() throws -> [Playlist] {
        try context.fetch(Playlist.allWithEntries())
    }

    /// The resolver over `playlists`, which must be all of them (fetched once by the caller,
    /// who may need them too).
    func resolver(among playlists: [Playlist]) throws -> QueueResolver {
        QueueResolver(
            state: try state(), playlists: playlists.map { $0.queuePlaylist(among: playlists) },
            playedEpisodes: playedEpisodes(in: playlists))
    }

    private func playedEpisodes(in playlists: [Playlist]) -> Set<EpisodeID> {
        var played: Set<EpisodeID> = []
        for playlist in playlists {
            for case let episode? in (playlist.entries ?? []).map(\.episode) where episode.isPlayed {
                played.insert(episode.episodeID)
            }
        }
        return played
    }

    // MARK: Resume points (N107)

    /// Every playlist's frontmost episode in Up Next, before an operation.
    func queuedEpisodes(_ resolver: QueueResolver) -> [PlaylistID: EpisodeID] {
        var result: [PlaylistID: EpisodeID] = [:]
        for id in resolver.playlists.keys {
            if let episode = resolver.nextQueuedEpisode(of: id) { result[id] = episode }
        }
        return result
    }

    /// Writes the resolver's state and the resume points (N107): a playlist the operation
    /// took over forgets its stored one. A playlist that was in Up Next before the operation
    /// (`before`) and is not any more stores its frontmost episode, unless it has one stored;
    /// if that episode ended or was skipped (`endsEpisode`), it forgets its stored point only
    /// when that was the ended episode. So single episodes passing through leave it alone.
    func write(_ resolver: QueueResolver, before: [PlaylistID: EpisodeID], endsEpisode: Bool) throws {
        for id in resolver.takenOverPlaylists {
            if let playlist = try playlist(id), playlist.resumeEpisode != nil { playlist.resumeEpisode = nil }
        }
        for (id, frontmost) in before
        where resolver.nextQueuedEpisode(of: id) == nil && !resolver.takenOverPlaylists.contains(id) {
            guard let playlist = try playlist(id) else { continue }
            let stored = playlist.resumeEpisode?.episodeID
            if endsEpisode {
                if stored == frontmost { playlist.resumeEpisode = nil }
            } else if stored == nil {
                playlist.resumeEpisode = try episode(frontmost)
            }
        }
        try write(resolver.state)
    }

    // MARK: State

    /// The stored Up Next. A store written before ADR 0008 may hold playlist blocks: they
    /// are taken over at their place once, the flat state is written back and the history
    /// (snapshots of the old shape) is cleared (A90).
    func state() throws -> UpNextState {
        let (state, blocks) = try storedState()
        guard !blocks.isEmpty else { return state }
        let playlists = try playlists()
        let resolver = QueueResolver(
            state: state, playlists: playlists.map { $0.queuePlaylist(among: playlists) },
            playedEpisodes: playedEpisodes(in: playlists))
        var flat = state
        for (_, id) in blocks { try playlist(id)?.resumeEpisode = nil }  // taken over: derived from now on (N107)
        for (index, id) in blocks.reversed() {
            // The running block goes on behind its episode, a waiting one starts at its stored
            // resume point ("ab Wiedergabestand", A90), not at an episode that happens to wait.
            let start = index == 0 && state.nowPlaying != nil ? state.nowPlaying : resolver.playlists[id]?.resumeEpisode
            flat.items.insert(contentsOf: resolver.takeover(of: id, startingAt: start).filter { $0 != state.nowPlaying }, at: index)
        }
        var seen: Set<EpisodeID> = Set([state.nowPlaying].compactMap { $0 })
        flat.items = flat.items.filter { seen.insert($0).inserted }
        try write(flat)
        try context.fetch(FetchDescriptor<UpNextSnapshot>()).forEach(context.delete)
        Logger.upNext.notice("Up Next migrated: \(blocks.count) playlist blocks taken over, history cleared")
        return flat
    }

    /// The items as stored: the flat state and, from before ADR 0008, the blocks with the
    /// index in `items` where their episodes belong. The running episode's own block (its
    /// playlist on the now-playing item) counts as a block at the front.
    private func storedState() throws -> (UpNextState, [(index: Int, playlist: PlaylistID)]) {
        var state = UpNextState()
        var blocks: [(index: Int, playlist: PlaylistID)] = []
        let items = try context.fetch(FetchDescriptor<QueueItem>(sortBy: [SortDescriptor(\.position)]))
        for item in items {
            if item.isNowPlaying {
                state.nowPlaying = item.episode?.episodeID
                if let playlist = item.playlist { blocks.insert((0, playlist.playlistID), at: 0) }
            } else if let episode = item.episode {
                state.items.append(episode.episodeID)
            } else if let playlist = item.playlist {
                blocks.append((state.items.count, playlist.playlistID))
            }
        }
        return (state, blocks)
    }

    /// Writes the state into the stored items: an item per episode is kept and moved, the
    /// others are deleted, missing ones inserted (one fetch for the episodes; the queue may
    /// hold hundreds after taking over "Alles"). Episodes that no longer exist are dropped.
    private func write(_ state: UpNextState) throws {
        let (stored, blocks) = try storedState()
        guard !blocks.isEmpty || stored != state else { return }
        var items: [UUID: QueueItem] = [:]
        for item in try context.fetch(FetchDescriptor<QueueItem>()) {
            guard let uuid = item.episode?.uuid, item.playlist == nil, items[uuid] == nil else {
                context.delete(item)
                continue
            }
            items[uuid] = item
        }
        let wanted = ([state.nowPlaying].compactMap { $0 } + state.items).map(\.uuid)
        let uuids = Set(wanted)
        for (uuid, item) in items where !uuids.contains(uuid) { context.delete(item) }
        let episodes = Dictionary(
            try context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { wanted.contains($0.uuid) })).map { ($0.uuid, $0) },
            uniquingKeysWith: { first, _ in first })
        if let now = state.nowPlaying {
            if let item = items[now.uuid] {
                item.isNowPlaying = true
                item.position = -1
            } else if let episode = episodes[now.uuid] {
                context.insert(QueueItem(nowPlaying: episode))
            }
        }
        for (index, id) in state.items.enumerated() {
            if let item = items[id.uuid] {
                item.isNowPlaying = false
                item.position = Double(index)
            } else if let episode = episodes[id.uuid] {
                context.insert(QueueItem(position: Double(index), episode: episode))
            }
        }
    }

    // MARK: History

    /// The stored snapshots; one that cannot be decoded (the shape before ADR 0008) is dropped.
    func history() throws -> UpNextHistory {
        let descriptor = FetchDescriptor<UpNextSnapshot>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        var snapshots: [UpNextSnapshotValue] = []
        for stored in try context.fetch(descriptor) {
            if let value = try? stored.value() { snapshots.append(value) } else { context.delete(stored) }
        }
        return UpNextHistory(snapshots: snapshots)
    }

    func write(_ history: UpNextHistory) throws {
        guard try self.history().snapshots != history.snapshots else { return }
        try context.fetch(FetchDescriptor<UpNextSnapshot>()).forEach(context.delete)
        for snapshot in history.snapshots { context.insert(try UpNextSnapshot(snapshot)) }
    }

    // MARK: Lookup

    /// Every episode that is in a playlist, by ID: one pass over the entries, cheaper than a
    /// `PlaylistContent` per playlist when only the episodes behind the resolver's IDs are needed.
    func episodesInPlaylists(_ playlists: [Playlist]) -> [EpisodeID: Episode] {
        var episodes: [EpisodeID: Episode] = [:]
        for playlist in playlists {
            for case let episode? in (playlist.entries ?? []).map(\.episode) {
                episodes[episode.episodeID] = episode
            }
        }
        return episodes
    }

    func episode(_ id: EpisodeID) throws -> Episode? {
        let uuid = id.uuid
        var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.uuid == uuid })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func playlist(_ id: PlaylistID) throws -> Playlist? {
        let uuid = id.uuid
        var descriptor = FetchDescriptor<Playlist>(predicate: #Predicate { $0.uuid == uuid })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
