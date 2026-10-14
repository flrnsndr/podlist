import PodlistKit
import SwiftData
import SwiftUI

/// Playlists tab (concept §6.6, N38, N92): all playlists in the user's order, each with its
/// own ▶ (tap and long press as in §4.4) and where it stands (A62). "Alles" comes first and
/// stays there (A64). Hidden playlists wait behind a row at the end (N66). Up Next has its
/// own tab (N92).
struct PlaylistsView: View {
    @Query(sort: \Playlist.displayOrder) private var playlists: [Playlist]
    @Query(sort: \QueueItem.position) private var queueItems: [QueueItem]
    @Environment(PlaylistService.self) private var service
    @Environment(UpNextService.self) private var upNext
    @Environment(HiddenPlaylistsReveal.self) private var hiddenPlaylists
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Group {
                if playlists.tags.isEmpty {  // "Alles" alone is no playlist yet
                    ContentUnavailableView {
                        Label("No Playlists Yet", systemImage: "music.note.list")
                    } description: {
                        Text("Playlists group your podcasts by topic.")
                    } actions: {
                        Button("New Playlist") { isCreating = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Playlists")
            .navigationDestination(for: Playlist.self) { PlaylistDetailView(playlist: $0) }
            .toolbar {
                if !playlists.tags.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Playlist", systemImage: "plus") { isCreating = true }
                        .accessibilityIdentifier("newPlaylistButton")
                }
            }
            .sheet(isPresented: $isCreating) { PlaylistEditorView(playlist: nil) }
        }
    }

    private var list: some View {
        // One resolver for the whole tab: what every playlist plays next.
        let upcoming = upNext.upcomingEpisodes(of: playlists)
        let split = playlists.tags.splitByHidden()
        return List {
            Section {
                if let everything = playlists.everything {
                    NavigationLink(value: everything) {
                        PlaylistRow(
                            playlist: everything, count: everything.shownEpisodes(among: playlists).count,
                            current: current, next: upcoming[everything.playlistID]?.first)
                    }
                    .accessibilityIdentifier("everythingRow")
                }
                rows(split.shown, upcoming: upcoming)
                if hiddenPlaylists.isRevealed {
                    rows(split.behindMore, upcoming: upcoming)
                }
                HiddenPlaylistsRow(count: split.behindMore.count)
            }
        }
    }

    /// One group of rows; moving stays within the group (N66). No swipe to delete: deleting
    /// lives in the editor (N67).
    private func rows(_ group: [Playlist], upcoming: [PlaylistID: [Episode]]) -> some View {
        ForEach(group) { playlist in
            NavigationLink(value: playlist) {
                PlaylistRow(
                    playlist: playlist, count: (playlist.entries ?? []).count,
                    current: current, next: upcoming[playlist.playlistID]?.first)
            }
            .accessibilityIdentifier("playlistRow")
        }
        .onMove { offsets, destination in
            try? service.movePlaylists(group, fromOffsets: offsets, toOffset: destination)
        }
    }

    private var current: QueueItem? { queueItems.first(where: \.isNowPlaying) }
}

/// A playlist with its ▶ and where it stands (A62): "Läuft: …", "Weiter bei: …" (the episode
/// at its cursor has a position), "Als Nächstes: …", or "Noch leer".
private struct PlaylistRow: View {
    let playlist: Playlist
    /// Its episodes; for "Alles" the ones it shows.
    let count: Int
    let current: QueueItem?
    /// The episode it plays next (its cursor or first episode).
    let next: Episode?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                PlaylistLabel(playlist: playlist)
                    .font(.body.weight(.semibold))
                Text(status)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("\(count) episodes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PlaylistStartButton(playlist: playlist) { isRunning, isPlaying in
                Image(systemName: isRunning && isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
                    .foregroundStyle(playlist.color)
                    .accessibilityLabel(isRunning
                        ? (isPlaying ? Text("Pause \(playlist.displayName)") : Text("Resume \(playlist.displayName)"))
                        : Text("Play \(playlist.displayName)"))
            }
            .buttonStyle(.borderless)
            .disabled(count == 0)
            .accessibilityIdentifier("playlistPlayButton")
        }
    }

    private var status: String {
        if let current, current.playlist == playlist, let episode = current.episode {
            return String(localized: "Playing: \(episode.title)")
        }
        guard let next else {
            return String(localized: "Empty")
        }
        return next.playbackPosition > 0
            ? String(localized: "Continue: \(next.title)")
            : String(localized: "Next: \(next.title)")
    }
}
