import PodlistKit
import SwiftData
import SwiftUI

/// "In welche Playlists?" (concept §4.5): right after subscribing, with playlists
/// preselected from the feed's categories, and later from the podcast detail. Hidden playlists
/// wait behind "Mehr ›" unless they were chosen when the sheet opened (N66).
struct AssignPlaylistsView: View {
    let podcast: Podcast
    /// Just subscribed: preselect by category and offer "Skip".
    var isAfterSubscribing = false
    var onFinish: () -> Void = {}

    @Query(sort: \Playlist.displayOrder) private var allPlaylists: [Playlist]
    /// Tags only: "Alles" is no tag (concept §4.1).
    private var playlists: [Playlist] { allPlaylists.tags }
    @Environment(PlaylistService.self) private var service
    @Environment(\.dismiss) private var dismiss
    @Environment(HiddenPlaylistsReveal.self) private var hiddenPlaylists
    @State private var rules: [UUID: AutoAddRule] = [:]
    /// Chosen when the sheet opened: shown even if hidden, so nothing vanishes while tapping.
    @State private var pinned: Set<UUID> = []
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    let split = playlists.splitByHidden(pinned: pinned)
                    FlowLayout {
                        ForEach(split.shown + (hiddenPlaylists.isRevealed ? split.behindMore : [])) { playlist in
                            PlaylistChip(playlist: playlist, isSelected: rules[playlist.uuid] != nil) {
                                toggle(playlist)
                            }
                        }
                        HiddenPlaylistsChip(count: split.behindMore.count)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text(podcast.title)
                } footer: {
                    Text("New episodes arrive in the inbox. Turn on New Episodes below to add them to a playlist automatically.")
                }
                let selected = playlists.filter { rules[$0.uuid] != nil }
                if !selected.isEmpty {
                    Section("New Episodes") {
                        ForEach(selected) { playlist in
                            AutoAddPicker(playlist: playlist, rule: binding(for: playlist))
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if isAfterSubscribing {
                        Button("Skip") { finish() }
                    } else {
                        Button("Cancel", role: .cancel) { finish() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { save() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let assignments = podcast.assignments ?? []
        if !assignments.isEmpty || !isAfterSubscribing {
            rules = Dictionary(assignments.compactMap { a in a.playlist.map { ($0.uuid, a.autoAdd) } },
                               uniquingKeysWith: { first, _ in first })
        } else {
            let suggested = PlaylistSuggestions.suggested(forCategories: podcast.categories, playlists: playlists.map(\.candidate))
            rules = Dictionary(suggested.map { ($0.uuid, AutoAddRule.off) }, uniquingKeysWith: { first, _ in first })
        }
        pinned = Set(rules.keys)
    }

    private func toggle(_ playlist: Playlist) {
        rules[playlist.uuid] = rules[playlist.uuid] == nil ? .off : nil  // N93
    }

    private func binding(for playlist: Playlist) -> Binding<AutoAddRule> {
        Binding(get: { rules[playlist.uuid] ?? .off }, set: { rules[playlist.uuid] = $0 })
    }

    private func save() {
        try? service.setAssignments(of: podcast, to: rules)
        finish()
    }

    private func finish() {
        onFinish()
        dismiss()
    }
}

/// Auto-add rule of one assignment. Top/bottom only matters for manual sort (concept §4.2),
/// so other playlists just offer on/off.
struct AutoAddPicker: View {
    let playlist: Playlist
    @Binding var rule: AutoAddRule

    var body: some View {
        if playlist.sort == .manual {
            Picker(selection: $rule) {
                Text("Off").tag(AutoAddRule.off)
                Text("Top").tag(AutoAddRule.top)
                Text("Bottom").tag(AutoAddRule.bottom)
            } label: {
                PlaylistLabel(playlist: playlist)
            }
            .pickerStyle(.menu)
        } else {
            Toggle(isOn: Binding(get: { rule != .off }, set: { rule = $0 ? .bottom : .off })) {
                PlaylistLabel(playlist: playlist)
            }
        }
    }
}
