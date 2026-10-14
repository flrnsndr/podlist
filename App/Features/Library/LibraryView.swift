import PodlistKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Bibliothek: subscribed podcasts as tiles, filtered by playlist (concept §4.1, §6.6). New
/// episodes are in the inbox ("Alle Folgen" is gone, N42). Adding by feed URL and the OPML
/// import live in the toolbar. Podcasts of hidden playlists only show under their chip (N65).
struct LibraryView: View {
    @Query(filter: #Predicate<Podcast> { $0.isSubscribed }, sort: \Podcast.title)
    private var podcasts: [Podcast]
    @Query(sort: \Playlist.displayOrder) private var allPlaylists: [Playlist]
    /// Tags only: "Alles" is no tag (concept §4.1).
    private var playlists: [Playlist] { allPlaylists.tags }
    @Environment(LibraryService.self) private var library
    @State private var filter = PlaylistFilter.all
    @State private var isAddingFeed = false
    @State private var isImportingOPML = false
    @State private var importResult: OPMLImportResult?
    @State private var importFailed = false
    @State private var isShowingSettings = false
    @State private var isShowingStorage = false

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 16)]

    var body: some View {
        NavigationStack {
            Group {
                if podcasts.isEmpty {
                    emptyState
                } else {
                    content
                        .refreshable { await library.refreshAll() }
                }
            }
            .navigationTitle("Library")
            .navigationDestination(for: Podcast.self) { PodcastDetailView(podcast: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
                        .accessibilityIdentifier("settingsButton")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Storage", systemImage: "internaldrive") { isShowingStorage = true }
                        .accessibilityIdentifier("storageButton")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        addMenuItems
                    } label: {
                        Label("Add Podcast", systemImage: "plus")
                    }
                }
            }
            .overlay { importProgressOverlay }
            .sheet(isPresented: $isAddingFeed) { AddFeedView() }
            .sheet(isPresented: $isShowingSettings) { SettingsView() }
            .sheet(isPresented: $isShowingStorage) { StorageSheet() }
            .fileImporter(isPresented: $isImportingOPML, allowedContentTypes: Self.opmlTypes) { result in
                Task { await importOPML(result) }
            }
            .alert("Import finished", isPresented: Binding(get: { importResult?.failed.isEmpty == true }, set: { if !$0 { importResult = nil } }),
                   presenting: importResult) { _ in
                Button("OK") {}
            } message: { result in
                Text(importSummary(result))
            }
            .sheet(isPresented: Binding(get: { importResult?.failed.isEmpty == false }, set: { if !$0 { importResult = nil } })) {
                if let importResult { OPMLImportResultView(result: importResult) }
            }
            .alert("The file could not be imported.", isPresented: $importFailed) {
                Button("OK") {}
            }
        }
    }

    private var content: some View {
        let shown = filteredPodcasts
        // Explicit spacing: the empty state sits exactly where it does in the inbox list.
        return ScrollView {
            VStack(spacing: 0) {
                PlaylistFilterBar(playlists: playlists, filter: $filter, identifierPrefix: "library")
                if shown.isEmpty {
                    filteredEmptyState
                        .padding(.top, PlaylistFilterBar.emptyStateGap)
                        .accessibilityIdentifier("libraryEmptyState")
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(shown) { podcast in
                            NavigationLink(value: podcast) {
                                PodcastTile(podcast: podcast)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 8)
                    .padding([.horizontal, .bottom])
                }
            }
        }
    }

    private var filteredPodcasts: [Podcast] {
        switch filter {
        case .all:
            podcasts.filter { !$0.isHiddenFromAll }
        case .withoutPlaylist:
            podcasts.filter { ($0.assignments ?? []).isEmpty }
        case .playlist(let id):
            podcasts.filter { ($0.assignments ?? []).contains { $0.playlist?.playlistID == id } }
        }
    }

    private var filteredEmptyState: some View {
        ContentUnavailableView("No Podcasts", systemImage: "line.3.horizontal.decrease.circle",
                               description: filter == .withoutPlaylist
                                   ? Text("Every podcast is in a playlist.")
                                   : Text("No subscribed podcast is assigned to this playlist."))
    }

    @ViewBuilder private var addMenuItems: some View {
        Button("Add Feed URL", systemImage: "link") { isAddingFeed = true }
        Button("Import OPML", systemImage: "square.and.arrow.down") { isImportingOPML = true }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Podcasts Yet", systemImage: "books.vertical")
        } description: {
            Text("Search for podcasts, add a feed URL or import your subscriptions as OPML.")
        } actions: {
            Button("Add Feed URL") { isAddingFeed = true }
            Button("Import OPML") { isImportingOPML = true }
        }
    }

    @ViewBuilder private var importProgressOverlay: some View {
        if let progress = library.importProgress {
            VStack(spacing: 12) {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                Text("Importing podcasts: \(progress.done) of \(progress.total)")
                    .font(.callout)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
        }
    }

    private static let opmlTypes: [UTType] = [UTType(filenameExtension: "opml"), .xml].compactMap { $0 }

    private func importOPML(_ result: Result<URL, any Error>) async {
        guard case .success(let url) = result else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            importResult = try await library.importOPML(data)
        } catch {
            importFailed = true
        }
    }

    private func importSummary(_ result: OPMLImportResult) -> String {
        var lines = [String(localized: "\(result.subscribed) podcasts subscribed.")]
        if result.alreadySubscribed > 0 {
            lines.append(String(localized: "\(result.alreadySubscribed) were already subscribed."))
        }
        return lines.joined(separator: "\n")
    }
}

/// A podcast in the library grid.
struct PodcastTile: View {
    let podcast: Podcast

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: podcast.artworkURL)
            Text(podcast.title)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .accessibilityElement(children: .combine)
    }
}
