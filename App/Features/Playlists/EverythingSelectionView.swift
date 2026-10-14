import PodlistKit
import SwiftData
import SwiftUI

/// What goes into "Alles" (concept §4.1, N71, N72): every playlist and every subscribed
/// podcast with a switch; off leaves it out. Hidden playlists come last and start off. A
/// long podcast list can be searched.
struct EverythingSelectionView: View {
    @Query(sort: \Playlist.displayOrder) private var allPlaylists: [Playlist]
    @Query(filter: #Predicate<Podcast> { $0.isSubscribed }) private var subscribed: [Podcast]
    @Environment(PlaylistService.self) private var service
    @State private var searchText = ""

    private var playlists: [Playlist] {
        let split = allPlaylists.tags.splitByHidden()
        return split.shown + split.behindMore
    }

    private var podcasts: [Podcast] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return subscribed
            .filter { query.isEmpty || $0.title.localizedStandardContains(query) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        Form {
            if searchText.isEmpty && !playlists.isEmpty {
                Section {
                    ForEach(playlists) { playlist in
                        Toggle(isOn: Binding(
                            get: { !playlist.isExcludedFromEverything },
                            set: { try? service.setExcluded(!$0, playlist: playlist) }
                        )) {
                            PlaylistLabel(playlist: playlist)
                        }
                        .accessibilityIdentifier("everythingPlaylistToggle")
                    }
                } header: {
                    Text("Playlists")
                } footer: {
                    Text("“Everything” shows the episodes of the playlists that are on. An episode stays as long as one of its playlists is on. Hidden playlists start off.")
                }
            }
            Section {
                ForEach(podcasts) { podcast in
                    Toggle(isOn: Binding(
                        get: { !podcast.isExcludedFromEverything },
                        set: { try? service.setExcluded(!$0, podcast: podcast) }
                    )) {
                        Label {
                            Text(podcast.title).lineLimit(2)
                        } icon: {
                            ArtworkView(url: podcast.artworkURL, cornerRadius: 6)
                                .frame(width: 28, height: 28)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityIdentifier("everythingPodcastToggle")
                }
            } header: {
                Text("Podcasts")
            } footer: {
                Text("Podcasts that are off are missing from “Everything” entirely.")
            }
        }
        .navigationTitle("Playlists & Podcasts")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("Search Podcasts"))
    }
}
