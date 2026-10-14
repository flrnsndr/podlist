import PodlistKit
import SwiftUI

/// The playlist filter of library and inbox (concept §4.10: chips "wie in der Bibliothek"):
/// "Alle", the shown playlists, "Ohne Playlist", then hidden playlists behind "Mehr ›" (N65,
/// N66). One view, so the chips sit at exactly the same place in both tabs. It scrolls with
/// the content: as a `safeAreaBar` its scroll edge effect sometimes stayed over the top of
/// the screen and swallowed every tap (iOS 26).
struct PlaylistFilterBar: View {
    let playlists: [Playlist]
    @Binding var filter: PlaylistFilter
    /// "library" or "inbox": identifiers `<prefix>FilterBar`, `<prefix>FilterWithoutPlaylist`.
    let identifierPrefix: String
    @Environment(HiddenPlaylistsReveal.self) private var hiddenPlaylists

    /// Space between the bar and the "nothing here" message of an empty filter.
    static let emptyStateGap: CGFloat = 48

    var body: some View {
        let split = playlists.splitByHidden()
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                PlaylistChip(title: String(localized: "All"), isSelected: filter == .all) { filter = .all }
                ForEach(split.shown) { playlistChip($0) }
                PlaylistChip(title: String(localized: "No Playlist"), symbolName: "tag.slash",
                             isSelected: filter == .withoutPlaylist) {
                    filter = filter == .withoutPlaylist ? .all : .withoutPlaylist
                }
                .accessibilityIdentifier("\(identifierPrefix)FilterWithoutPlaylist")
                if hiddenPlaylists.isRevealed {
                    ForEach(split.behindMore) { playlistChip($0) }
                }
                HiddenPlaylistsChip(count: split.behindMore.count)
            }
            .padding(.horizontal)
        }
        .accessibilityLabel(Text("Filter"))
        .accessibilityIdentifier("\(identifierPrefix)FilterBar")
        .padding(.bottom, 8)
        // A chip that went away (collapsed, hidden, deleted) takes its filter along.
        .onChange(of: chipIDs(split)) { _, ids in
            if case .playlist(let id) = filter, !ids.contains(id) { filter = .all }
        }
    }

    private func chipIDs(_ split: (shown: [Playlist], behindMore: [Playlist])) -> [PlaylistID] {
        (split.shown + (hiddenPlaylists.isRevealed ? split.behindMore : [])).map(\.playlistID)
    }

    private func playlistChip(_ playlist: Playlist) -> some View {
        PlaylistChip(playlist: playlist, isSelected: filter == .playlist(playlist.playlistID)) {
            filter = filter == .playlist(playlist.playlistID) ? .all : .playlist(playlist.playlistID)
        }
    }
}
