import PodlistKit
import SwiftData
import SwiftUI

/// "Zu Playlist …" (concept §4.5): multiple choice, checkmarks show where the episode
/// already is, one tap per playlist without confirmation, recently used playlists first.
/// Hidden playlists wait behind "Mehr ›" unless the episode was in them when it opened (N66).
struct AddToPlaylistView: View {
    let episode: Episode
    @Query(sort: \Playlist.displayOrder) private var allPlaylists: [Playlist]
    /// Tags only: "Alles" is no tag (concept §4.1).
    private var playlists: [Playlist] { allPlaylists.tags }
    @Environment(PlaylistService.self) private var service
    @Environment(\.dismiss) private var dismiss
    @Environment(HiddenPlaylistsReveal.self) private var hiddenPlaylists
    @AppStorage("recentPlaylists") private var recentStorage = ""
    /// Fixed when the sheet opens, so rows do not jump while tapping.
    @State private var recentOrder: [UUID] = []
    /// Playlists the episode was in when the sheet opened: shown even if hidden.
    @State private var pinned: Set<UUID> = []

    var body: some View {
        NavigationStack {
            let split = ordered.splitByHidden(pinned: pinned)
            List {
                ForEach(split.shown + (hiddenPlaylists.isRevealed ? split.behindMore : [])) { playlist in
                    row(playlist)
                }
                HiddenPlaylistsRow(count: split.behindMore.count)
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                recentOrder = Self.decode(recentStorage)
                pinned = Set(playlists.filter(contains).map(\.uuid))
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ playlist: Playlist) -> some View {
        let contains = contains(playlist)
        return Button {
            toggle(playlist, contains: contains)
        } label: {
            HStack {
                PlaylistLabel(playlist: playlist)
                    .foregroundStyle(.primary)
                Spacer()
                if contains {
                    Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                }
            }
        }
        .accessibilityAddTraits(contains ? .isSelected : [])
        .accessibilityIdentifier("addToPlaylist.\(playlist.displayName)")
    }

    private var ordered: [Playlist] {
        let rank = Dictionary(recentOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return playlists.enumerated().sorted { a, b in
            switch (rank[a.element.uuid], rank[b.element.uuid]) {
            case let (x?, y?): x < y
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.offset < b.offset
            }
        }.map(\.element)
    }

    private func contains(_ playlist: Playlist) -> Bool {
        (episode.playlistEntries ?? []).contains { $0.playlist == playlist }
    }

    private func toggle(_ playlist: Playlist, contains: Bool) {
        if contains {
            try? service.remove(episode, from: playlist)
        } else {
            try? service.add(episode, to: playlist)
            var recent = Self.decode(recentStorage).filter { $0 != playlist.uuid }
            recent.insert(playlist.uuid, at: 0)
            recentStorage = recent.prefix(10).map(\.uuidString).joined(separator: ",")
        }
    }

    private static func decode(_ storage: String) -> [UUID] {
        storage.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }
}

extension View {
    /// The actions every episode row offers (concept §4.5): "Als Nächstes" and "Am Ende"
    /// by swiping right, played status and "Zu Playlist …" by swiping left (with `remove`
    /// first, e.g. "Remove" in a playlist), all of them and the download in the context menu.
    func episodeActions(_ episode: Episode, remove: EpisodeRemoveAction? = nil) -> some View {
        modifier(EpisodeActions(episode: episode, remove: remove))
    }
}

/// A destructive row action shown before the others, e.g. removing from a playlist.
struct EpisodeRemoveAction {
    let title: LocalizedStringKey
    let action: () -> Void
}

private struct EpisodeActions: ViewModifier {
    let episode: Episode
    let remove: EpisodeRemoveAction?
    @Environment(UpNextService.self) private var upNext
    @State private var isAddingToPlaylist = false

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading) {
                playNextButton.tint(.orange)
                playLastButton.tint(.blue)
            }
            .swipeActions(edge: .trailing) {
                if let remove {
                    Button(remove.title, systemImage: "minus.circle", role: .destructive, action: remove.action)
                }
                PlayedToggle(episode: episode)
                addToPlaylistButton.tint(.indigo)
            }
            .contextMenu {
                playNextButton
                playLastButton
                Divider()
                PlayedToggle(episode: episode)
                addToPlaylistButton
                DownloadButton(episode: episode)
                if let remove {
                    Button(remove.title, systemImage: "minus.circle", role: .destructive, action: remove.action)
                }
            }
            .sheet(isPresented: $isAddingToPlaylist) { AddToPlaylistView(episode: episode) }
    }

    private var playNextButton: some View {
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") {
            withAnimation { upNext.playNext(episode) }
        }
    }

    private var playLastButton: some View {
        Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") { upNext.playLast(episode) }
    }

    private var addToPlaylistButton: some View {
        Button("Add to Playlist…", systemImage: "music.note.list") { isAddingToPlaylist = true }
    }
}
