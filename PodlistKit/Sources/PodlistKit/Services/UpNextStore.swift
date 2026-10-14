import Foundation
import SwiftData

/// Persistence of Up Next (ADR 0004): builds a `QueueResolver` from the stored `QueueItem`s
/// and all playlists, and writes its state, the playlists' cursors and the history back.
/// Shared by `UpNextService` and `PlaylistEntryRemoval`. Does not save.
struct UpNextStore {
    let context: ModelContext

    // MARK: Resolver

    func resolver() throws -> QueueResolver {
        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        var played: Set<EpisodeID> = []
        for playlist in playlists {
            for case let episode? in (playlist.entries ?? []).map(\.episode) where episode.isPlayed {
                played.insert(episode.episodeID)
            }
        }
        return QueueResolver(
            state: try state(), playlists: playlists.map { $0.queuePlaylist(among: playlists) }, playedEpisodes: played)
    }

    /// Writes the resolver's state and the cursors it moved.
    func write(_ resolver: QueueResolver) throws {
        for playlist in try context.fetch(FetchDescriptor<Playlist>()) {
            guard let queued = resolver.playlists[playlist.playlistID],
                  playlist.resumeEpisode?.episodeID != queued.resumeEpisode else { continue }
            playlist.resumeEpisode = try queued.resumeEpisode.flatMap { cursor in
                try (playlist.entries ?? []).lazy.compactMap(\.episode).first { $0.episodeID == cursor } ?? episode(cursor)
            }
        }
        try write(resolver.state)
    }

    /// One operation that never starts playback (editing a playlist, the played policy).
    func update(_ operation: (inout QueueResolver) -> Void) throws {
        var resolver = try resolver()
        operation(&resolver)
        try write(resolver)
    }

    /// Before a change that can take episodes out of "Alles" (leaving out, deleting a
    /// playlist): its cursor moves past the episodes that leave (N71). `change` returns the
    /// playlists as they will be afterwards; it may already change flags, not delete.
    func keepingEverythingsPlace(_ change: () throws -> [Playlist]) throws {
        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        var resolver = try resolver()
        let before = playlists.everything.map { Set($0.content(among: playlists).entries.map(\.episode.id)) } ?? []
        let after = try change()
        guard let everything = after.everything else { return }
        let leaving = before.subtracting(everything.content(among: after).entries.map(\.episode.id))
        guard !leaving.isEmpty else { return }
        resolver.episodesWillBeRemoved(leaving, from: everything.playlistID)
        try write(resolver)
    }

    /// Episodes just landed in playlists: those in "Alles" come first there (N98, A78), also
    /// when they were in it already and moved to its top (A80). `addedAt`: the date of the new
    /// entries; an episode whose "Hinzugefügt" in Alles is another one did not move (a
    /// playlist left out of Alles).
    func episodesWereAdded(_ episodes: Set<EpisodeID>, addedAt: Date? = nil) throws {
        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        guard let everything = playlists.everything else { return }
        let arrived = Set(everything.content(among: playlists).entries
            .filter { episodes.contains($0.episode.id) && (addedAt == nil || $0.addedAt == addedAt) }
            .map(\.episode.id))
        guard !arrived.isEmpty else { return }
        try update { $0.episodesArrived(arrived, in: everything.playlistID) }
    }

    // MARK: State

    func state() throws -> UpNextState {
        var state = UpNextState()
        let items = try context.fetch(FetchDescriptor<QueueItem>(sortBy: [SortDescriptor(\.position)]))
        for item in items {
            if item.isNowPlaying {
                if let episode = item.episode {
                    state.nowPlaying = NowPlaying(episode: episode.episodeID, playlist: item.playlist?.playlistID)
                }
            } else if let episode = item.episode {
                state.items.append(.episode(episode.episodeID))
            } else if let playlist = item.playlist {
                state.items.append(.playlist(playlist.playlistID))
            }
        }
        return state
    }

    /// Replaces the stored items. Episodes and playlists that no longer exist are dropped.
    private func write(_ state: UpNextState) throws {
        guard try self.state() != state else { return }
        try context.fetch(FetchDescriptor<QueueItem>()).forEach(context.delete)
        if let now = state.nowPlaying, let episode = try episode(now.episode) {
            context.insert(QueueItem(nowPlaying: episode, playlist: try now.playlist.flatMap(playlist)))
        }
        for (index, item) in state.items.enumerated() {
            switch item {
            case .episode(let id):
                if let episode = try episode(id) { context.insert(QueueItem(position: Double(index), episode: episode)) }
            case .playlist(let id):
                if let playlist = try playlist(id) { context.insert(QueueItem(position: Double(index), playlist: playlist)) }
            }
        }
    }

    // MARK: History

    func history() throws -> UpNextHistory {
        let descriptor = FetchDescriptor<UpNextSnapshot>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return UpNextHistory(snapshots: try context.fetch(descriptor).compactMap { try? $0.value() })
    }

    func write(_ history: UpNextHistory) throws {
        guard try self.history().snapshots != history.snapshots else { return }
        try context.fetch(FetchDescriptor<UpNextSnapshot>()).forEach(context.delete)
        for snapshot in history.snapshots { context.insert(try UpNextSnapshot(snapshot)) }
    }

    // MARK: Lookup

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
