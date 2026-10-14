import PodlistKit
import SwiftData
import SwiftUI

/// Inbox tab (Eingang, concept §4.10): open episodes of the last 14 days to add, play next or
/// dismiss; done and dismissed ones leave it (N74, N77). Episodes done in this session wait
/// below, reduced, until the app goes to the background (A67). Episodes of hidden playlists'
/// podcasts only show under their chip (N65).
struct InboxView: View {
    @Query(InboxService.candidates(now: .now)) private var candidates: [Episode]
    @Query(sort: \Playlist.displayOrder) private var allPlaylists: [Playlist]
    /// Tags only: "Alles" is no tag (concept §4.1).
    private var playlists: [Playlist] { allPlaylists.tags }
    @Environment(InboxService.self) private var inbox
    @Environment(LibraryService.self) private var library
    @Environment(\.scenePhase) private var scenePhase
    @State private var filter = PlaylistFilter.all
    @State private var selectedEpisode: Episode?
    /// Here, not in the row: the row leaves the list as soon as the episode lands in a playlist.
    @State private var addingToPlaylist: Episode?

    var body: some View {
        let shown = InboxService.shown(candidates, filter: filter, now: .now)
        let recentlyDone = inbox.recentlyDone(candidates, filter: filter, now: .now)
        NavigationStack {
            // Always a list, so pull to refresh also works on an empty inbox.
            List {
                PlaylistFilterBar(playlists: playlists, filter: $filter, identifierPrefix: "inbox")
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                ForEach(shown) { episode in
                    InboxRow(episode: episode, onOpen: { selectedEpisode = episode },
                             onAddToPlaylist: { addingToPlaylist = episode })
                }
                if shown.isEmpty {
                    // Under the chips, at the same place as in the library.
                    emptyState
                        .padding(.top, PlaylistFilterBar.emptyStateGap)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("inboxEmptyState")
                } else {
                    dismissAllButton(shown)
                }
                if !recentlyDone.isEmpty {
                    Section {
                        ForEach(recentlyDone) { episode in
                            InboxDoneRow(episode: episode, onOpen: { selectedEpisode = episode },
                                         onAddToPlaylist: { addingToPlaylist = episode })
                        }
                    } header: {
                        Text("inbox.justDone")
                            .accessibilityIdentifier("inboxJustDone")
                    }
                }
            }
            .listStyle(.plain)
            // The filter row is lower than a list row; otherwise its chips sit lower than in
            // the library.
            .environment(\.defaultMinListRowHeight, 0)
            .animation(.default, value: shown.map(\.id))
            .animation(.default, value: recentlyDone.map(\.id))
            .refreshable { await library.refreshAll() }
            // Episodes seen open stay below once done (A67); the background empties the list
            // (`InboxService.endSession`), so what shows counts as seen again on return.
            .onChange(of: shown.map(\.id), initial: true) { inbox.sawOpen(shown) }
            .onChange(of: scenePhase) { _, phase in if phase == .active { inbox.sawOpen(shown) } }
            .onAppear { inbox.sawOpen(shown) }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add All") { try? inbox.addAll(shown) }
                        .disabled(InboxRules.episodesToAddAll(shown.compactMap(\.inboxValue)).isEmpty)
                        .accessibilityIdentifier("inboxAddAll")
                }
            }
            .sheet(item: $selectedEpisode) { EpisodeDetailView(episode: $0) }
            .sheet(item: $addingToPlaylist) { AddToPlaylistView(episode: $0) }
        }
    }

    /// "Rest aussortieren (n)" under the last open episode, away from "Alle hinzufügen" (N78).
    private func dismissAllButton(_ shown: [Episode]) -> some View {
        Button {
            try? inbox.discardAll(shown)
        } label: {
            Label("Dismiss Rest (\(shown.count))", systemImage: "tray.and.arrow.up")
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity)
        }
        // Quieter than "Alle hinzufügen": grey, nothing is deleted.
        .buttonStyle(.bordered)
        .tint(.gray)
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("inboxDismissAll")
    }

    @ViewBuilder private var emptyState: some View {
        if filter == .all {
            ContentUnavailableView("No New Episodes", systemImage: "tray",
                                   description: Text("New episodes of your podcasts arrive here."))
        } else {
            filteredEmptyState
        }
    }

    private var filteredEmptyState: some View {
        ContentUnavailableView("Nothing Here", systemImage: "line.3.horizontal.decrease.circle",
                               description: filter == .withoutPlaylist
                                   ? Text("There are no new episodes of podcasts without a playlist.")
                                   : Text("There are no new episodes of podcasts in this playlist."))
    }
}

/// One open inbox episode with its actions (concept §4.10).
private struct InboxRow: View {
    let episode: Episode
    let onOpen: () -> Void
    let onAddToPlaylist: () -> Void
    @Environment(InboxService.self) private var inbox

    /// The podcast's playlists it is not in yet: after partial auto-add only the rest (N75).
    private var missingPlaylists: [Playlist] {
        let current = Set((episode.playlistEntries ?? []).compactMap(\.playlist))
        return (episode.podcast?.assignments ?? []).compactMap(\.playlist)
            .filter { !current.contains($0) }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            info
            actionBar
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .leading) {
            addButton.tint(.green)
            playNextButton.tint(.orange)
        }
        .swipeActions(edge: .trailing) {
            dismissButton.tint(.gray)
        }
        .contextMenu {
            addButton
            playNextButton
            addToPlaylistButton
            dismissButton
        }
    }

    /// The common episode row; actions instead of ▶ (concept §4.10).
    private var info: some View {
        EpisodeRow(episode: episode, showsPodcast: true, showsPlayButton: false)
            .contentShape(.rect)
            .onTapGesture(perform: onOpen)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(infoLabel))
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("inboxRow")
    }

    private var infoLabel: String {
        var parts = [episode.podcast?.title, episode.title, episode.publishedAt.formatted(.dateTime.day().month().year())]
            .compactMap { $0 }
        if let duration = episode.duration { parts.append(duration.durationText) }
        return parts.joined(separator: ", ")
    }

    private var actionBar: some View {
        HStack {
            let missing = missingPlaylists
            if !missing.isEmpty {
                Button {
                    try? inbox.addToPodcastPlaylists(episode)
                } label: {
                    Text("Add to \(missing.map(\.displayName).formatted(.list(type: .and)))")
                        .lineLimit(1)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.small)
                .accessibilityIdentifier("inboxAdd")
            }
            Spacer()
            Menu {
                addToPlaylistButton
                playNextButton
                dismissButton
            } label: {
                Label("More", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            // Same symbol as every "More" menu, as a small button next to "Add to …".
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .accessibilityIdentifier("inboxMore")
        }
        .buttonStyle(.borderless)
    }

    private var addButton: some View {
        Button("Add", systemImage: "text.badge.plus") { try? inbox.addToPodcastPlaylists(episode) }
            .disabled(missingPlaylists.isEmpty)
    }

    private var addToPlaylistButton: some View {
        Button("Add to Playlist…", systemImage: "music.note.list", action: onAddToPlaylist)
            .accessibilityIdentifier("inboxAddToPlaylist")
    }

    private var playNextButton: some View {
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { inbox.playNext(episode) }
            .accessibilityIdentifier("inboxPlayNext")
    }

    /// "Aussortieren" (N77): grey, no trash can; nothing is deleted.
    private var dismissButton: some View {
        Button("Dismiss", systemImage: "tray.and.arrow.up") { try? inbox.discard(episode) }
            .accessibilityIdentifier("inboxDismiss")
    }
}

/// An episode done in this session, reduced and grey under "Gerade erledigt" (N74, A57): with
/// the playlists it is in, or just "Erledigt".
private struct InboxDoneRow: View {
    let episode: Episode
    let onOpen: () -> Void
    let onAddToPlaylist: () -> Void

    private var currentPlaylists: [Playlist] {
        (episode.playlistEntries ?? []).compactMap(\.playlist).sorted { $0.displayOrder < $1.displayOrder }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.caption)
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .font(.subheadline)
                    .lineLimit(1)
                FlowLayout(spacing: 4) {
                    ForEach(currentPlaylists) { PlaylistTag(playlist: $0) }
                }
            }
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
        .contentShape(.rect)
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("inboxDoneRow")
        .swipeActions(edge: .trailing) { addToPlaylistButton.tint(.indigo) }
        .contextMenu { addToPlaylistButton }
    }

    private var accessibilityText: String {
        let playlists = currentPlaylists.map(\.displayName)
        let parts = [episode.podcast?.title, episode.title, String(localized: "inbox.done")].compactMap { $0 }
            + (playlists.isEmpty ? [] : [playlists.formatted(.list(type: .and))])
        return parts.joined(separator: ", ")
    }

    private var addToPlaylistButton: some View {
        Button("Add to Playlist…", systemImage: "music.note.list", action: onAddToPlaylist)
            .accessibilityIdentifier("inboxAddToPlaylist")
    }
}
