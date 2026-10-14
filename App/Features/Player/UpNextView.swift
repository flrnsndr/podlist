import PodlistKit
import SwiftData
import SwiftUI

/// Up Next, its own tab (concept §4.4, §6.6, N92): the running episode, the waiting single episodes and
/// playlist blocks (each with all episodes it will play), and "Vorherige Warteschlangen".
/// Swiping away or reordering never changes a playlist.
struct UpNextView: View {
    @Query(sort: \QueueItem.position) private var items: [QueueItem]
    @Query(sort: \UpNextSnapshot.createdAt, order: .reverse) private var snapshots: [UpNextSnapshot]
    @Environment(UpNextService.self) private var upNext
    @Environment(\.undoManager) private var undoManager
    @State private var selected: SelectedEpisode?

    var body: some View {
        let current = items.first(where: \.isNowPlaying)
        let waiting = items.filter { !$0.isNowPlaying }
        let rows = rows(for: waiting)
        let history = snapshots.compactMap { try? $0.value() }
        List {
            if let current, let episode = current.episode {
                Section("Now Playing") {
                    // Swiping it away plays the next item (like ⏭ without coming back).
                    ForEach([current]) { _ in
                        QueueEpisodeRow(episode: episode, playlist: current.playlist)
                            .onTapGesture { selected = SelectedEpisode(episode: episode, playlist: current.playlist) }
                            .moveDisabled(true)
                            .accessibilityIdentifier("upNextNowPlaying")
                    }
                    .onDelete { _ in upNext.removeNowPlaying() }
                }
            }
            Section("Queue") {
                if rows.isEmpty {
                    Text("Nothing queued. Add episodes with \"Play Next\" or \"Play Last\", or play a playlist.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    rowView(row)
                        .moveDisabled(!row.isItem)
                        .deleteDisabled(!row.isItem)
                }
                .onMove { offsets, destination in
                    let (itemOffsets, itemDestination) = Self.itemMove(rows, fromOffsets: offsets, toOffset: destination)
                    upNext.moveItems(fromOffsets: itemOffsets, toOffset: itemDestination)
                }
                .onDelete { offsets in
                    for offset in offsets where rows[offset].isItem { upNext.remove(rows[offset].item) }
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
        .sheet(item: $selected) { EpisodeDetailView(episode: $0.episode, playlist: $0.playlist) }
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

    // MARK: Rows

    /// A list row: a waiting item (single episode or block header) or an episode of a block.
    private struct Row: Identifiable {
        let item: QueueItem
        let isItem: Bool
        var episode: Episode?
        var playlist: Playlist?
        var id: RowID { RowID(item: item.persistentModelID, episode: isItem ? nil : episode?.uuid) }
    }

    private struct RowID: Hashable {
        let item: PersistentIdentifier
        let episode: UUID?
    }

    private func rows(for waiting: [QueueItem]) -> [Row] {
        var rows: [Row] = []
        for item in waiting {
            if let episode = item.episode {
                rows.append(Row(item: item, isItem: true, episode: episode))
            } else if let playlist = item.playlist {
                rows.append(Row(item: item, isItem: true, playlist: playlist))
                for episode in upNext.upcomingEpisodes(of: playlist) {
                    rows.append(Row(item: item, isItem: false, episode: episode, playlist: playlist))
                }
            }
        }
        return rows
    }

    @ViewBuilder private func rowView(_ row: Row) -> some View {
        if row.isItem, let playlist = row.playlist {
            BlockHeaderRow(playlist: playlist)
        } else if let episode = row.episode {
            QueueEpisodeRow(episode: episode, playlist: nil, block: row.isItem ? nil : row.playlist)
                .padding(.leading, row.isItem ? 0 : 16)
                .onTapGesture { selected = SelectedEpisode(episode: episode, playlist: row.playlist) }
        }
    }

    /// Maps a move of list rows to a move of Up Next items: only item rows move, and a
    /// destination inside a block means after that block.
    private static func itemMove(_ rows: [Row], fromOffsets offsets: IndexSet, toOffset destination: Int) -> (IndexSet, Int) {
        var itemIndex: [Int: Int] = [:]
        var count = 0
        for (index, row) in rows.enumerated() where row.isItem {
            itemIndex[index] = count
            count += 1
        }
        let itemOffsets = IndexSet(offsets.compactMap { itemIndex[$0] })
        let itemDestination = rows.prefix(destination).count(where: \.isItem)
        return (itemOffsets, itemDestination)
    }

    private struct SelectedEpisode: Identifiable {
        let episode: Episode
        let playlist: Playlist?
        var id: PersistentIdentifier { episode.persistentModelID }
    }
}

/// An episode in Up Next: the common `EpisodeRow`, for
/// the running episode with its playlist. An episode of a block says so to VoiceOver, where
/// the indentation does not show.
struct QueueEpisodeRow: View {
    let episode: Episode
    let playlist: Playlist?
    var block: Playlist?

    var body: some View {
        EpisodeRow(episode: episode, showsPodcast: true, showsPlayButton: false, tags: playlist.map { [$0] } ?? [])
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
            .accessibilityValue(block.map { Text("In playlist \($0.displayName)") } ?? Text(verbatim: ""))
            .accessibilityAddTraits(.isButton)
    }
}

/// The header of a playlist block: the playlist with color and symbol.
private struct BlockHeaderRow: View {
    let playlist: Playlist

    var body: some View {
        PlaylistLabel(playlist: playlist)
            .font(.headline)
            .accessibilityLabel(Text("Playlist \(playlist.displayName)"))
            .accessibilityIdentifier("upNextBlock")
    }
}

/// One former queue: what was playing, when, and what was waiting.
private struct HistoryRow: View {
    let snapshot: UpNextSnapshotValue
    @Environment(UpNextService.self) private var upNext

    var body: some View {
        let episode = snapshot.state.nowPlaying.flatMap { upNext.episode($0.episode) }
        let playlists = snapshot.state.items.compactMap { item -> Playlist? in
            guard case .playlist(let id) = item else { return nil }
            return upNext.playlist(id)
        }
        let singles = snapshot.state.items.count { if case .episode = $0 { true } else { false } }
        VStack(alignment: .leading, spacing: 4) {
            Text(episode?.title ?? String(localized: "Nothing playing"))
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            HStack(spacing: 8) {
                ForEach(playlists) { PlaylistTag(playlist: $0) }
                if singles > 0 {
                    Text("\(singles) episodes")
                }
            }
            .font(.caption)
            .lineLimit(1)
            Text(snapshot.createdAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
