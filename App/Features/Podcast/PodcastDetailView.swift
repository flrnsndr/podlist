import PodlistKit
import SwiftData
import SwiftUI

/// Podcast-Detail: header and all episodes, newest first.
struct PodcastDetailView: View {
    let podcast: Podcast
    @Query private var episodes: [Episode]
    @Environment(LibraryService.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var selectedEpisode: Episode?
    @State private var isConfirmingUnsubscribe = false
    @State private var isSummaryExpanded = false
    @State private var isAssigningPlaylists = false
    @State private var isShowingSettings = false

    init(podcast: Podcast) {
        self.podcast = podcast
        let id = podcast.uuid
        _episodes = Query(filter: #Predicate<Episode> { $0.podcast?.uuid == id },
                          sort: \Episode.publishedAt, order: .reverse)
    }

    var body: some View {
        List {
            Section {
                header
            }
            Section("Episodes") {
                ForEach(episodes) { episode in
                    Button { selectedEpisode = episode } label: { EpisodeRow(episode: episode, addsToPodcastPlaylists: true) }
                        .buttonStyle(.plain)
                        .episodeActions(episode)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(podcast.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { try? await library.refresh(podcast) }
        .sheet(item: $selectedEpisode) { EpisodeDetailView(episode: $0) }
        .sheet(isPresented: $isAssigningPlaylists) { AssignPlaylistsView(podcast: podcast) }
        .sheet(isPresented: $isShowingSettings) { PodcastSettingsView(podcast: podcast) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Playlists…", systemImage: "music.note.list") { isAssigningPlaylists = true }
                    Button("Podcast Settings…", systemImage: "slider.horizontal.3") { isShowingSettings = true }
                        .accessibilityIdentifier("podcastSettings")
                    if let link = podcast.link {
                        Link(destination: link) { Label("Website", systemImage: "safari") }
                    }
                    Button("Unsubscribe", systemImage: "minus.circle", role: .destructive) {
                        isConfirmingUnsubscribe = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
            }
        }
        .confirmationDialog("Unsubscribe from this podcast?", isPresented: $isConfirmingUnsubscribe,
                            titleVisibility: .visible) {
            Button("Unsubscribe", role: .destructive) {
                try? library.unsubscribe(podcast)
                dismiss()
            }
        } message: {
            Text("Episodes in playlists, in the queue or with listening progress are kept.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                ArtworkView(url: podcast.artworkURL, cornerRadius: 12)
                    .frame(width: 112)
                VStack(alignment: .leading, spacing: 4) {
                    Text(podcast.title).font(.title3.bold())
                    if let author = podcast.author {
                        Text(author).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            if let summary = podcast.summary {
                Text(HTMLText.plainText(fromHTML: summary))
                    .font(.callout)
                    .lineLimit(isSummaryExpanded ? nil : 3)
                    .onTapGesture { isSummaryExpanded.toggle() }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(isSummaryExpanded ? Text("Shows less") : Text("Shows the full description"))
            }
            assignedPlaylists
        }
        .padding(.vertical, 4)
    }
}

extension PodcastDetailView {
    /// The podcast's playlists ("tags"); tapping opens the assignment sheet.
    private var assignedPlaylists: some View {
        let playlists = (podcast.assignments ?? []).compactMap(\.playlist).sorted { $0.displayOrder < $1.displayOrder }
        return FlowLayout {
            ForEach(playlists) { playlist in
                PlaylistChip(playlist: playlist, isSelected: true) { isAssigningPlaylists = true }
            }
            PlaylistChip(title: String(localized: playlists.isEmpty ? "Add to Playlists" : "Edit"),
                         symbolName: playlists.isEmpty ? "plus" : "pencil", isSelected: false) {
                isAssigningPlaylists = true
            }
            .accessibilityIdentifier("editPlaylists")
        }
    }
}

/// "Als gespielt markieren" / "Als ungehört markieren".
struct PlayedToggle: View {
    let episode: Episode
    @Environment(LibraryService.self) private var library
    @Environment(PlayerController.self) private var player

    var body: some View {
        if episode.isPlayed {
            Button("Mark as Unplayed", systemImage: "circle") { try? library.markUnplayed(episode) }
        } else {
            Button("Mark as Played", systemImage: "checkmark.circle") { player.markPlayed(episode) }
                .tint(.green)
        }
    }
}
