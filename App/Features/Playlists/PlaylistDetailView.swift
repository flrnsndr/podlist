import PodlistKit
import SwiftData
import SwiftUI

/// One playlist: its episodes in the chosen sort, playing it, sort menu, podcasts and
/// settings (concept §4.2, §4.4, §6.6). While episodes of the playlist are in Up Next, the
/// list has two parts (N106): "In der Warteschlange" in Up Next's order (dragging reorders
/// Up Next, swiping takes an episode out of it) and "Danach", the draft in the playlist's sort.
/// "Alles" mirrors the other playlists: no removing, no reordering of the draft, one fixed
/// sort, and what goes into it instead of its podcasts (§4.1, N70–N73, N97).
struct PlaylistDetailView: View {
    let playlist: Playlist
    /// All playlists, which "Alles" mirrors.
    @Query(Playlist.allWithEntries()) private var allPlaylists: [Playlist]
    @Query(filter: #Predicate<Podcast> { $0.isSubscribed && $0.isExcludedFromEverything })
    private var excludedPodcasts: [Podcast]
    /// Only so the view updates when Up Next changes.
    @Query(sort: \QueueItem.position) private var queueItems: [QueueItem]
    @Environment(PlaylistService.self) private var service
    @Environment(UpNextService.self) private var upNext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isTabSelected) private var isTabSelected
    @State private var selectedEpisode: Episode?
    @State private var isEditing = false
    /// Confirmed in the editor (N67): close the sheet, leave this view, then delete, so
    /// nothing reads the deleted playlist.
    @State private var isDeleting = false
    @State private var hidesPlayed = false

    /// Dragging in the draft works in every playlist but "Alles"; a sorted one becomes manual (N96).
    private var canReorder: Bool { !playlist.isEverything }

    private struct Parts {
        /// Its episodes in Up Next, the running one first (empty if none is queued).
        var live: [Episode] = []
        /// The rest in the playlist's sort, with the filters of this screen.
        var draft: [Episode] = []
        var isRunning = false
        var isEmpty: Bool { live.isEmpty && draft.isEmpty }
    }

    private var parts: Parts {
        var parts = Parts()
        let split = upNext.split(of: playlist, among: allPlaylists)
        parts.live = split.live
        let running = queueItems.first(where: \.isNowPlaying)?.episode
        parts.isRunning = running != nil && split.live.first == running
        let queued = Set(split.live.map(\.persistentModelID))
        var draft = playlist.shownEpisodes(among: allPlaylists).filter { !queued.contains($0.persistentModelID) }
        if hidesPlayed, playlist.playedPolicy == .keep { draft = draft.filter { !$0.isPlayed } }
        parts.draft = draft
        return parts
    }

    var body: some View {
        // Every save in the app updates this view, also behind another tab; the sort over all
        // entries ("Alles": every playlist's) and the resolver wait until the tab is in front.
        let parts = isTabSelected ? parts : Parts()
        let memberships = isTabSelected ? everythingMemberships : [:]
        Group {
            if playlist.isEverything && parts.isEmpty {
                ContentUnavailableView(
                    "No Episodes", systemImage: playlist.symbolName,
                    description: Text("The episodes of all your playlists show up here."))
            } else if !playlist.isEverything && (playlist.entries ?? []).isEmpty {
                ContentUnavailableView(
                    "No Episodes", systemImage: playlist.symbolName,
                    description: Text("Episodes arrive from assigned podcasts or via \"Add to Playlist\"."))
            } else {
                List {
                    if !parts.live.isEmpty {
                        liveSection(parts.live, in: memberships)
                    }
                    if !parts.draft.isEmpty {
                        draftSections(parts.draft, in: memberships, titled: !parts.live.isEmpty)
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
            if !parts.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    PlaylistStartButton(playlist: playlist, isRunning: parts.isRunning) { isRunning, isPlaying in
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
            if (canReorder && !parts.draft.isEmpty) || parts.live.count > (parts.isRunning ? 2 : 1) {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            ToolbarItem(placement: .primaryAction) { optionsMenu }
        }
    }

    // MARK: Sections

    /// "In der Warteschlange" (N106): the running episode stays put; the waiting ones are
    /// dragged within Up Next (`UpNextService.move`), each swipes out of Up Next.
    private func liveSection(_ live: [Episode], in memberships: [UUID: [Playlist]]) -> some View {
        let running = queueItems.first(where: \.isNowPlaying)?.episode
        let waiting = running != nil && live.first == running ? Array(live.dropFirst()) : live
        return Section {
            if waiting.count < live.count, let running = live.first {
                row(running, in: memberships, remove: EpisodeRemoveAction(title: "Remove from Queue") {
                    upNext.removeNowPlaying()
                })
                .moveDisabled(true)
            }
            ForEach(waiting) { episode in
                row(episode, in: memberships, remove: EpisodeRemoveAction(title: "Remove from Queue") {
                    upNext.remove(episode)
                })
            }
            .onMove { offsets, destination in
                guard let offset = offsets.first else { return }
                var reordered = waiting
                reordered.move(fromOffsets: offsets, toOffset: destination)
                let episode = waiting[offset]
                guard let index = reordered.firstIndex(of: episode) else { return }
                upNext.move(episode, behind: index == 0 ? nil : reordered[index - 1])
            }
        } header: {
            Text("In the Queue")
                .accessibilityIdentifier("playlistLiveHeader")
        }
    }

    /// The draft: the rest of the playlist in its sort, "Danach" when a live part is above it.
    @ViewBuilder private func draftSections(_ draft: [Episode], in memberships: [UUID: [Playlist]], titled: Bool) -> some View {
        if playlist.sort == .podcast {
            if titled {
                Section {} header: {
                    Text("After That")
                        .accessibilityIdentifier("playlistDraftHeader")
                }
            }
            ForEach(sections(of: draft), id: \.podcastID) { section in
                Section(section.title) {
                    ForEach(section.episodes) { draftRow($0, in: memberships) }
                        .onMove(perform: canReorder ? { offsets, destination in
                            try? service.moveEntries(
                                of: playlist, shown: section.episodes, fromOffsets: offsets, toOffset: destination)
                        } : nil)
                }
            }
        } else {
            Section {
                ForEach(draft) { draftRow($0, in: memberships) }
                    .onMove(perform: canReorder ? { offsets, destination in
                        try? service.moveEntries(of: playlist, shown: draft, fromOffsets: offsets, toOffset: destination)
                    } : nil)
            } header: {
                if titled {
                    Text("After That")
                        .accessibilityIdentifier("playlistDraftHeader")
                }
            }
        }
    }

    /// "Alles" mixes playlists: for each episode the playlists it is in, shown as pills (empty elsewhere).
    private var everythingMemberships: [UUID: [Playlist]] {
        guard playlist.isEverything else { return [:] }
        var result: [UUID: [Playlist]] = [:]
        for tag in allPlaylists.tags {
            for entry in tag.entries ?? [] {
                if let episode = entry.episode { result[episode.uuid, default: []].append(tag) }
            }
        }
        return result
    }

    private func draftRow(_ episode: Episode, in memberships: [UUID: [Playlist]]) -> some View {
        // "Alles" never changes another playlist (N73).
        row(episode, in: memberships, remove: playlist.isEverything ? nil : EpisodeRemoveAction(title: "Remove") {
            try? service.remove(episode, from: playlist)
        })
    }

    private func row(_ episode: Episode, in memberships: [UUID: [Playlist]], remove: EpisodeRemoveAction?) -> some View {
        Button { selectedEpisode = episode } label: {
            EpisodeRow(episode: episode, showsPodcast: true, playlist: playlist, tags: memberships[episode.uuid] ?? [])
        }
        .buttonStyle(.plain)
        .episodeActions(episode, remove: remove)
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
