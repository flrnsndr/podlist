import PodlistKit
import SwiftData
import SwiftUI

/// Up Next, its own tab (concept §4.4, §6.6, N92, ADR 0008): the running episode, the waiting
/// episodes as one flat list (A89; a row shows its playlists as pills), and "Vorherige
/// Warteschlangen". Swiping away or reordering never changes a playlist (N104).
struct UpNextView: View {
    @Query(sort: \QueueItem.position) private var items: [QueueItem]
    @Query(sort: \UpNextSnapshot.createdAt, order: .reverse) private var snapshots: [UpNextSnapshot]
    @Environment(UpNextService.self) private var upNext
    @Environment(\.undoManager) private var undoManager
    @State private var selected: Episode?

    var body: some View {
        let current = items.first(where: \.isNowPlaying)?.episode
        // Items from before ADR 0008 without an episode (blocks) are taken over on the first
        // read of the store; until then they have no row.
        let waiting = items.filter { !$0.isNowPlaying && $0.episode != nil }
        let history = snapshots.compactMap { try? $0.value() }
        List {
            Section("Queue") {
                // The running episode and the waiting items share one box. The running row sits outside the
                // `ForEach`, so the offsets of `onMove`/`onDelete` stay those of the waiting rows.
                if let current {
                    // Swiping it away plays the next item (like ⏭ without coming back).
                    QueueEpisodeRow(episode: current)
                        .onTapGesture { selected = current }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete", role: .destructive) { upNext.removeNowPlaying() }
                        }
                        .accessibilityIdentifier("upNextNowPlaying")
                        .listRowSeparatorTint(.secondary, edges: .bottom)
                }
                if waiting.isEmpty {
                    Text("Nothing queued. Add episodes with \"Play Next\" or \"Play Last\", or play a playlist.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(waiting) { item in
                    if let episode = item.episode {
                        QueueEpisodeRow(episode: episode)
                            .onTapGesture { selected = episode }
                            .accessibilityIdentifier("upNextEpisode")
                    }
                }
                .onMove { offsets, destination in
                    upNext.moveItems(fromOffsets: offsets, toOffset: destination)
                }
                .onDelete { offsets in
                    for offset in offsets { if let episode = waiting[offset].episode { upNext.remove(episode) } }
                }
            }
            if !history.isEmpty {
                Section {
                    ForEach(history, id: \.createdAt) { snapshot in
                        Button {
                            undoManager?.removeAllActions(withTarget: upNext)
                            upNext.restore(snapshot)
                        } label: { HistoryRow(snapshot: snapshot) }
                            .buttonStyle(.plain)
                            .accessibilityHint(Text("Restores this queue"))
                    }
                } header: {
                    Text("Previous Queues")
                } footer: {
                    Text("Tap a queue to restore it. The current one is kept here as well.")
                }
            }
        }
        .navigationTitle("Queue")
        .sheet(item: $selected) { EpisodeDetailView(episode: $0) }
        .toolbar {
            if !waiting.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear", role: .destructive) { upNext.clear() }
                        .accessibilityIdentifier("clearUpNextButton")
                }
                ToolbarItem(placement: .primaryAction) { EditButton() }
            }
        }
    }
}

/// An episode in Up Next: the common `EpisodeRow` with the playlists it is in as pills (A89).
struct QueueEpisodeRow: View {
    let episode: Episode

    private var tags: [Playlist] {
        (episode.playlistEntries ?? []).compactMap(\.playlist).tags.sorted { $0.displayOrder < $1.displayOrder }
    }

    var body: some View {
        EpisodeRow(episode: episode, showsPodcast: true, showsPlayButton: false, tags: tags)
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }
}

/// One former queue: what was playing, when, and how much was waiting.
private struct HistoryRow: View {
    let snapshot: UpNextSnapshotValue
    @Environment(UpNextService.self) private var upNext

    var body: some View {
        let episode = snapshot.state.nowPlaying.flatMap { upNext.episode($0) }
        VStack(alignment: .leading, spacing: 4) {
            Text(episode?.title ?? String(localized: "Nothing playing"))
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            if !snapshot.state.items.isEmpty {
                Text("\(snapshot.state.items.count) episodes")
                    .font(.caption)
                    .lineLimit(1)
            }
            Text(snapshot.createdAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
