import Foundation
import SwiftData

/// The one place where episodes leave playlists, shared by `PlaylistService` (by hand)
/// and `LibraryService` (played policy). Up Next is not involved (ADR 0008, A88): an
/// episode that is queued stays queued, and a resume point that leaves its playlist reads
/// as empty (`Playlist.queuePlaylist(among:)`, N107).
enum PlaylistEntryRemoval {
    /// Removes the episode by hand. Does not save.
    static func remove(_ episode: Episode, from playlist: Playlist, context: ModelContext) throws {
        (playlist.entries ?? []).filter { $0.episode == episode }.forEach(context.delete)
    }

    /// Played policy (concept §4.3): a played episode leaves every "remove" playlist,
    /// except while it is in the player. Does not save.
    static func applyPlayedPolicy(to episode: Episode, context: ModelContext) throws {
        guard episode.isPlayed else { return }
        let playlists = (episode.playlistEntries ?? []).compactMap(\.playlist)
        let policies = playlists.map { PlaylistPolicy(playlistID: $0.playlistID, policy: $0.playedPolicy) }
        let ids = PlayedRules.playlistsToRemoveFrom(policies, isNowPlaying: episode.isNowPlaying)
        guard !ids.isEmpty else { return }
        for entry in episode.playlistEntries ?? [] where entry.playlist.map({ ids.contains($0.playlistID) }) == true {
            context.delete(entry)
        }
    }
}
