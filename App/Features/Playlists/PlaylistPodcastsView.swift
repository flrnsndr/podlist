import PodlistKit
import SwiftData
import SwiftUI

/// The podcasts assigned to a playlist with their auto-add rule (concept §4.1, §4.2).
struct PlaylistPodcastsView: View {
    let playlist: Playlist
    @Query(filter: #Predicate<Podcast> { $0.isSubscribed }, sort: \Podcast.title)
    private var subscribed: [Podcast]
    @Environment(PlaylistService.self) private var service

    private var assignments: [PlaylistAssignment] {
        (playlist.assignments ?? [])
            .filter { $0.podcast != nil }
            .sorted { ($0.podcast?.title ?? "").localizedStandardCompare($1.podcast?.title ?? "") == .orderedAscending }
    }

    private var unassigned: [Podcast] {
        let assigned = Set((playlist.assignments ?? []).compactMap { $0.podcast?.uuid })
        return subscribed.filter { !assigned.contains($0.uuid) }
    }

    /// Top and bottom only make sense for a manual order (concept §4.2).
    private var isManual: Bool { playlist.sort == .manual }

    var body: some View {
        List {
            Section {
                if assignments.isEmpty {
                    Text("No podcasts assigned yet.").foregroundStyle(.secondary)
                }
                ForEach(assignments) { assignment in
                    if let podcast = assignment.podcast {
                        assignedRow(assignment, podcast: podcast)
                    }
                }
            } header: {
                Text("Assigned Podcasts")
            } footer: {
                Text("New episodes are added automatically only for podcasts where it is turned on.")
            }
            if !unassigned.isEmpty {
                Section("Add Podcasts") {
                    ForEach(unassigned) { podcast in
                        HStack(spacing: 12) {
                            ArtworkView(url: podcast.artworkURL).frame(width: 44)
                            Text(podcast.title).lineLimit(2)
                            Spacer()
                            Button("Add \(podcast.title)", systemImage: "plus.circle") {
                                try? service.assign(podcast, to: playlist, autoAdd: .off)  // N93
                            }
                            .labelStyle(.iconOnly)
                            .font(.title2)
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .navigationTitle("Podcasts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func assignedRow(_ assignment: PlaylistAssignment, podcast: Podcast) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ArtworkView(url: podcast.artworkURL).frame(width: 44)
                Text(podcast.title).font(.headline).lineLimit(2)
            }
            Picker("Add New Episodes", selection: Binding(
                get: { isManual ? assignment.autoAdd : (assignment.autoAdd == .off ? .off : .bottom) },
                set: { try? service.assign(podcast, to: playlist, autoAdd: $0) }
            )) {
                Text("Off").tag(AutoAddRule.off)
                if isManual {
                    Text("Top").tag(AutoAddRule.top)
                    Text("Bottom").tag(AutoAddRule.bottom)
                } else {
                    Text("On").tag(AutoAddRule.bottom)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button("Remove", systemImage: "minus.circle", role: .destructive) {
                try? service.unassign(podcast, from: playlist)
            }
        }
    }
}
