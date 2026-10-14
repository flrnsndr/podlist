import Foundation

/// Hidden playlists (concept §4.1, N65): a podcast whose playlists are all hidden is left out
/// of "Alle" in the library and the inbox; it still shows under each of its playlists. A
/// visible playlist wins, and a podcast without playlists is never hidden. In lists of
/// playlists the hidden ones wait behind "Mehr ›" (N66).
public enum HiddenPlaylists {
    public static func hidesPodcast(in playlists: Set<PlaylistID>, hidden: Set<PlaylistID>) -> Bool {
        !playlists.isEmpty && playlists.isSubset(of: hidden)
    }

    /// A list of playlists for display (N66): `shown` always, `behindMore` only after "Mehr ›",
    /// each in the given order. `pinned` hidden playlists (already chosen when a sheet opened)
    /// stay among the shown ones, so a choice never disappears.
    public static func split(
        _ playlists: [(id: PlaylistID, isHidden: Bool)], pinned: Set<PlaylistID> = []
    ) -> (shown: [PlaylistID], behindMore: [PlaylistID]) {
        let isBehindMore = { (playlist: (id: PlaylistID, isHidden: Bool)) in playlist.isHidden && !pinned.contains(playlist.id) }
        return (playlists.filter { !isBehindMore($0) }.map(\.id), playlists.filter(isBehindMore).map(\.id))
    }
}
