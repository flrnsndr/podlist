import PodlistKit
import SwiftUI

/// Sheet to create or edit a playlist: name, color, symbol, its podcasts, played policy,
/// auto-download and hidden (concept §4.1, §4.3, §4.7, §4.8, N65). Editing ends with
/// "Delete Playlist", the only way to delete one (N67). "Alles" only has name, color, symbol,
/// what goes into it and played policy, and cannot be deleted (A64).
struct PlaylistEditorView: View {
    /// `nil` = create a new playlist.
    let playlist: Playlist?
    /// Called after the user confirmed deleting; the presenter closes its views first and
    /// then deletes, so no view reads the deleted playlist. `nil` = no delete button.
    var onDelete: (() -> Void)?
    @Environment(PlaylistService.self) private var service
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorKey: String
    @State private var symbolName: String
    @State private var playedPolicy: PlayedPolicy
    @State private var autoDownload: Bool
    @State private var isHidden: Bool
    @State private var isConfirmingDelete = false

    init(playlist: Playlist?, onDelete: (() -> Void)? = nil) {
        self.playlist = playlist
        self.onDelete = onDelete
        _name = State(initialValue: playlist?.displayName ?? "")
        _colorKey = State(initialValue: playlist?.colorKey ?? PlaylistPalette.colorKeys[7])
        _symbolName = State(initialValue: playlist?.symbolName ?? PlaylistPalette.symbols[0])
        _playedPolicy = State(initialValue: playlist?.playedPolicy ?? .remove)
        _autoDownload = State(initialValue: playlist?.autoDownload ?? true)  // N89
        _isHidden = State(initialValue: playlist?.isHidden ?? false)
    }

    private var isEverything: Bool { playlist?.isEverything ?? false }

    private var canSave: Bool {
        playlist != nil || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(playlist?.defaultName ?? String(localized: "Name"), text: $name)
                        .accessibilityIdentifier("playlistNameField")
                }
                Section("Color") { colorGrid }
                Section("Symbol") { symbolGrid }
                if let playlist {
                    Section {
                        if playlist.isEverything {
                            // "Alles" has no podcasts of its own, only what goes into it (N71).
                            NavigationLink("Playlists & Podcasts") { EverythingSelectionView() }
                                .accessibilityIdentifier("everythingSelectionEditorLink")
                        } else {
                            NavigationLink {
                                PlaylistPodcastsView(playlist: playlist)
                            } label: {
                                LabeledContent("Podcasts") {
                                    Text(playlist.assignedPodcastCount, format: .number)
                                }
                            }
                            .accessibilityIdentifier("playlistPodcastsLink")
                        }
                    }
                }
                // "Alles" always removes played episodes (N99).
                if !isEverything {
                    Section {
                        Picker("Played episodes", selection: $playedPolicy) {
                            Text("Remove").tag(PlayedPolicy.remove)
                            Text("Keep").tag(PlayedPolicy.keep)
                        }
                        .pickerStyle(.segmented)
                    } footer: {
                        Text("Remove: played episodes leave the playlist. Keep: they stay, dimmed, and play again from the start.")
                    }
                }
                Section {
                    Toggle("Download Automatically", isOn: $autoDownload)
                        .accessibilityIdentifier("autoDownloadToggle")
                } footer: {
                    if isEverything {
                        Text("Downloads every unplayed episode in Everything, also new ones, even if their playlist does not download automatically.")
                    } else {
                        Text("Downloads every unplayed episode of the playlist, also new ones.")
                    }
                }
                // "Alles" is no tag to hide (A64).
                if !isEverything {
                    Section {
                        Toggle("Hide Under All", isOn: $isHidden)
                            .accessibilityIdentifier("hiddenPlaylistToggle")
                    } footer: {
                        Text("Its podcasts show in the library and the inbox only under this playlist, not under All, unless they are also in a visible playlist. It is also left out of “Everything”.")
                    }
                }
                if playlist != nil, onDelete != nil, !isEverything {
                    Section {
                        Button("Delete Playlist", role: .destructive) { isConfirmingDelete = true }
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("deletePlaylistButton")
                    }
                }
            }
            .navigationTitle(playlist == nil ? Text("New Playlist") : Text("Edit Playlist"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("savePlaylistButton")
                }
            }
            // An alert, not an action sheet: it sits apart from the button, so a double tap
            // cannot confirm by accident (N67).
            .alert(
                Text("Delete “\(playlist?.displayName ?? "")”?"),
                isPresented: $isConfirmingDelete, presenting: playlist
            ) { _ in
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: { playlist in
                Text(Self.deletionConsequences(of: playlist))
            }
        }
    }

    /// What deleting takes with it, in numbers (N67).
    private static func deletionConsequences(of playlist: Playlist) -> String {
        var sentences: [String] = []
        let podcasts = playlist.assignedPodcastCount
        if podcasts > 0 {
            sentences.append(String(localized: "\(podcasts) podcasts lose this playlist as their tag."))
        }
        let episodes = (playlist.entries ?? []).count
        if episodes > 0 {
            sentences.append(String(localized: "Its \(episodes) episodes, where it stands and its settings are lost."))
        }
        if !(playlist.queueItems ?? []).isEmpty {
            sentences.append(String(localized: "It leaves the queue."))
        }
        sentences.append(String(localized: "The episodes themselves stay in your library. This cannot be undone."))
        return sentences.joined(separator: "\n\n")
    }

    private var colorGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
            ForEach(PlaylistPalette.colorKeys, id: \.self) { key in
                Button {
                    colorKey = key
                } label: {
                    Circle()
                        .fill(PlaylistPalette.color(for: key).gradient)
                        .frame(width: 36, height: 36)
                        .overlay {
                            if key == colorKey {
                                Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(LocalizedStringKey(key.capitalized)))
                .accessibilityAddTraits(key == colorKey ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private var symbolGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
            ForEach(PlaylistPalette.symbols, id: \.self) { symbol in
                Button {
                    symbolName = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(symbol == symbolName ? Color.white : Color.primary)
                        .frame(width: 40, height: 40)
                        .background(symbol == symbolName ? PlaylistPalette.color(for: colorKey) : Color.clear, in: .rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.3)))
                }
                .buttonStyle(.plain)
                // ASSUMPTION: the SF Symbol name is an acceptable VoiceOver label for symbols.
                .accessibilityLabel(symbol)
                .accessibilityAddTraits(symbol == symbolName ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if let playlist {
                let customName = (trimmed.isEmpty || trimmed == playlist.defaultName) ? nil : trimmed
                try service.update(playlist, customName: customName, colorKey: colorKey, symbolName: symbolName)
                if playedPolicy != playlist.playedPolicy { try service.setPlayedPolicy(playedPolicy, of: playlist) }
                if autoDownload != playlist.autoDownload { try service.setAutoDownload(autoDownload, of: playlist) }
                if isHidden != playlist.isHidden { try service.setHidden(isHidden, of: playlist) }
            } else {
                let created = try service.createPlaylist(name: trimmed, colorKey: colorKey, symbolName: symbolName)
                if playedPolicy == .keep { try service.setPlayedPolicy(.keep, of: created) }
                if !autoDownload { try service.setAutoDownload(false, of: created) }
                if isHidden { try service.setHidden(true, of: created) }
            }
            dismiss()
        } catch {
            // The service logs; the sheet stays open so nothing is lost.
        }
    }
}

private extension Playlist {
    var assignedPodcastCount: Int { (assignments ?? []).count(where: { $0.podcast != nil }) }
}
