import Foundation
import SwiftData

/// The one place where episodes leave playlists, shared by `PlaylistService` (by hand)
/// and `LibraryService` (played policy). Either way a cursor pointing at the episode moves
/// on to its successor first, so the playlist never loses its place (concept §4.4, ADR 0004).
enum PlaylistEntryRemoval {
    /// Removes the episode by hand. If it is running from this playlist's block, it plays
    /// to its end as a single episode (N13). Does not save.
    static func remove(_ episode: Episode, from playlist: Playlist, context: ModelContext) throws {
        let entries = (playlist.entries ?? []).filter { $0.episode == episode }
        guard !entries.isEmpty else { return }
        let ids = try withEverything([playlist.playlistID], ifLeftBy: episode, context: context)
        try UpNextStore(context: context).update {
            $0.episodeWillBeRemoved(episode.episodeID, from: ids)
        }
        entries.forEach(context.delete)
    }

    /// Played policy (concept §4.3): a played episode leaves every "remove" playlist,
    /// except while it is in the player. Does not save.
    static func applyPlayedPolicy(to episode: Episode, context: ModelContext) throws {
        guard episode.isPlayed else { return }
        let playlists = (episode.playlistEntries ?? []).compactMap(\.playlist)
        let policies = playlists.map { PlaylistPolicy(playlistID: $0.playlistID, policy: $0.playedPolicy) }
        let ids = PlayedRules.playlistsToRemoveFrom(policies, isNowPlaying: episode.isNowPlaying)
        guard !ids.isEmpty else { return }
        let cursors = try withEverything(ids, ifLeftBy: episode, context: context)
        try UpNextStore(context: context).update {
            $0.playedEpisodeWillBeRemoved(episode.episodeID, from: cursors)
        }
        for entry in episode.playlistEntries ?? [] where entry.playlist.map({ ids.contains($0.playlistID) }) == true {
            context.delete(entry)
        }
    }

    /// `ids` plus "Alles" if the episode leaves it with these playlists (N71): then the
    /// cursor of "Alles" moves on too.
    private static func withEverything(_ ids: [PlaylistID], ifLeftBy episode: Episode, context: ModelContext) throws -> [PlaylistID] {
        guard episode.isInEverything(), !episode.isInEverything(leaving: Set(ids)),
              let everything = try context.fetch(FetchDescriptor<Playlist>()).everything else { return ids }
        return ids + [everything.playlistID]
    }
}
