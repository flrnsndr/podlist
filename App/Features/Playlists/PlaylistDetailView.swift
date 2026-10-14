import PodlistKit
import SwiftData
import SwiftUI

/// One playlist: its episodes in the chosen sort, playing it, sort menu, podcasts and
/// settings (concept §4.2, §4.4, §6.6). "Alles" mirrors the other playlists: no removing, no
/// reordering, one fixed sort, and what goes into it instead of its podcasts (§4.1, N70–N73, N97).
struct PlaylistDetailView: View {
    let playlist: Playlist
    /// All playlists, which "Alles" mirrors.
    @Query private var allPlaylists: [Playlist]
    @Query(filter: #Predicate<Podcast> { $0.isSubscribed && $0.isExcludedFromEverything })
    private var excludedPodcasts: [Podcast]
    @Environment(PlaylistService.self) private var service
    @Environment(\.dismiss) private var dismiss
    @State private var selectedEpisode: Episode?
    @State private var isEditing = false
    /// Confirmed in the editor (N67): close the sheet, leave this view, then delete, so
    /// nothing reads the deleted playlist.
    @State private var isDeleting = false
    @State private var hidesPlayed = false

    /// Dragging works in every playlist but "Alles"; a sorted one becomes manual (N96).
    private var canReorder: Bool { !playlist.isEverything }

    private var visibleEpisodes: [Episode] {
        let episodes = playlist.shownEpisodes(among: allPlaylists)
        guard hidesPlayed, playlist.playedPolicy == .keep else { return episodes }
        return episodes.filter { !$0.isPlayed }
    }

    var body: some View {
        let episodes = visibleEpisodes
        Group {
            if playlist.isEverything && episodes.isEmpty {
                ContentUnavailableView(
                    "No Episodes", systemImage: playlist.symbolName,
                    description: Text("The episodes of all your playlists show up here."))
            } else if !playlist.isEverything && (playlist.entries ?? []).isEmpty {
                ContentUnavailableView(
                    "No Episodes", systemImage: playlist.symbolName,
                    description: Text("Episodes arrive from assigned podcasts or via \"Add to Playlist\"."))
            } else {
                List {
                    if playlist.sort == .podcast {
                        ForEach(sections(of: episodes), id: \.podcastID) { section in
                            Section(section.title) {
                                ForEach(section.episodes) { row($0) }
                                    .onMove(perform: canReorder ? { offsets, destination in
                                        try? service.moveEntries(
                                            of: playlist, shown: section.episodes, fromOffsets: offsets, toOffset: destination)
                                    } : nil)
                            }
                        }
                    } else {
                        ForEach(episodes) { row($0) }
                            .onMove(perform: canReorder ? { offsets, destination in
                                try? service.moveEntries(of: playlist, shown: episodes, fromOffsets: offsets, toOffset: destination)
                            } : nil)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(playlist.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedEpisode) { EpisodeDetailView(episode: $0, playlist: playlist) }
        .sheet(isPresented: $isEditing, onDismiss: { if isDeleting { dismiss() } }) {
            // "Alles" cannot be deleted (A64).
            PlaylistEditorView(playlist: playlist, onDelete: playlist.isEverything ? nil : { isDeleting = true })
        }
        .onDisappear {
            if isDeleting { try? service.delete(playlist) }
        }
        .toolbar {
            if !episodes.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    PlaylistStartButton(playlist: playlist) { isRunning, isPlaying in
                        if isRunning && isPlaying {
                            Label("Pause", systemImage: "pause.fill")
                        } else if isRunning {
                            Label("Resume", systemImage: "play.fill")
                        } else {
                            Label("Play Playlist", systemImage: "play.fill")
                        }
                    }
                    .accessibilityIdentifier("playPlaylistButton")
                }
            }
            if playlist.playedPolicy == .keep {
                ToolbarItem(placement: .primaryAction) {
                    Toggle("Hide Played", systemImage: "eye.slash", isOn: $hidesPlayed)
                        .toggleStyle(.button)
                }
            }
            if canReorder && !episodes.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            ToolbarItem(placement: .primaryAction) { optionsMenu }
        }
    }

    private func row(_ episode: Episode) -> some View {
        Button { selectedEpisode = episode } label: {
            EpisodeRow(episode: episode, showsPodcast: true, playlist: playlist)
        }
        .buttonStyle(.plain)
        // "Alles" never changes another playlist (N73).
        .episodeActions(episode, remove: playlist.isEverything ? nil : EpisodeRemoveAction(title: "Remove") {
            try? service.remove(episode, from: playlist)
        })
    }

    private struct EpisodeSection {
        let podcastID: PodcastID
        let title: String
        var episodes: [Episode]
    }

    /// The "by podcast" sections: the sorted episodes already come section by section.
    private func sections(of episodes: [Episode]) -> [EpisodeSection] {
        var sections: [EpisodeSection] = []
        for episode in episodes {
            let podcastID = episode.info.podcastID
            if sections.last?.podcastID == podcastID {
                sections[sections.count - 1].episodes.append(episode)
            } else {
                sections.append(EpisodeSection(podcastID: podcastID, title: episode.podcast?.title ?? "", episodes: [episode]))
            }
        }
        return sections
    }

    // MARK: Menu

    private var optionsMenu: some View {
        Menu {
            // "Alles" has one fixed sort, newest added first (N97).
            if !playlist.isEverything {
                Picker("Sort By", selection: Binding(
                    get: { playlist.sort },
                    set: { try? service.setSort($0, ascending: playlist.sortAscending, of: playlist) }
                )) {
                    Text("Manual").tag(PlaylistSort.manual)
                    Text("Release Date").tag(PlaylistSort.published)
                    Text("Date Added").tag(PlaylistSort.added)
                    Text("Title").tag(PlaylistSort.title)
                    Text("Duration").tag(PlaylistSort.duration)
                    Text("Podcast").tag(PlaylistSort.podcast)
                }
                if playlist.sort != .manual {
                    Picker("Direction", selection: Binding(
                        get: { playlist.sortAscending },
                        set: { try? service.setSort(playlist.sort, ascending: $0, of: playlist) }
                    )) {
                        switch playlist.sort {
                        case .title:
                            Text("A to Z").tag(true)
                            Text("Z to A").tag(false)
                        case .duration:
                            Text("Shortest First").tag(true)
                            Text("Longest First").tag(false)
                        default:
                            Text("Oldest First").tag(true)
                            Text("Newest First").tag(false)
                        }
                    }
                }
                Divider()
            }
            Button("Edit Playlist", systemImage: "pencil") { isEditing = true }
            if playlist.isEverything {
                NavigationLink {
                    EverythingSelectionView()
                } label: {
                    Label {
                        Text("Playlists & Podcasts")
                        let leftOut = allPlaylists.tags.count(where: \.isExcludedFromEverything) + excludedPodcasts.count
                        if leftOut > 0 { Text("\(leftOut) Left Out") }
                    } icon: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                .accessibilityIdentifier("everythingSelectionLink")
            } else {
                NavigationLink {
                    PlaylistPodcastsView(playlist: playlist)
                } label: {
                    Label("Podcasts", systemImage: "square.stack")
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis")
        }
        .accessibilityIdentifier("playlistMenu")
    }
}
