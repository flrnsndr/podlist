import PodlistKit
import SwiftData
import SwiftUI
import os

/// Settings → Benachrichtigungen (N35, N87): the main switch, then every subscribed podcast
/// nested under its playlists, each playlist with a switch for all its podcasts. Visible
/// playlists and "Ohne Playlist" first; hidden ones behind "Mehr ›" (N66). The main switch
/// and a group's switch can be undone, one step, with the banner. A hint when iOS does not
/// allow notifications (A47).
struct NotificationSettingsView: View {
    @Query(filter: #Predicate<Podcast> { $0.isSubscribed }) private var podcasts: [Podcast]
    @Query(sort: \Playlist.displayOrder) private var allPlaylists: [Playlist]
    @Environment(NotificationScheduler.self) private var notifications
    @Environment(HiddenPlaylistsReveal.self) private var reveal
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private var groups: (shown: [NotificationGroup], hidden: [NotificationGroup]) {
        NotificationGroups.groups(
            podcasts: podcasts.map(\.notificationPodcast),
            playlists: allPlaylists.tags.map { ($0.playlistID, $0.isHidden) })
    }

    var body: some View {
        let groups = groups
        let podcastsByID = Dictionary(podcasts.map { (PodcastID($0.uuid), $0) }, uniquingKeysWith: { first, _ in first })
        let playlistsByID = Dictionary(allPlaylists.map { ($0.playlistID, $0) }, uniquingKeysWith: { first, _ in first })
        Form {
            if notifications.authorization == .denied {
                Section {
                    Text("Notifications are turned off for Podlist in the iOS Settings.")
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                    }
                }
            }
            Section {
                Toggle("All Notifications", isOn: Binding(
                    get: { notifications.isEnabled }, set: { notifications.setEnabled($0) }))
                    .accessibilityIdentifier("notificationsMainToggle")
            } footer: {
                if notifications.isEnabled {
                    Text("Get a notification when a podcast has a new episode. A podcast in several playlists has one switch.")
                } else {
                    Text("Paused. Each podcast keeps its setting for when you turn notifications back on.")
                }
            }
            ForEach(groups.shown) { group in
                groupSection(group, podcasts: podcastsByID, playlists: playlistsByID)
            }
            if !groups.hidden.isEmpty {
                Section {
                    HiddenPlaylistsRow(count: groups.hidden.count)
                }
                if reveal.isRevealed {
                    ForEach(groups.hidden) { group in
                        groupSection(group, podcasts: podcastsByID, playlists: playlistsByID)
                    }
                }
            }
        }
        .navigationTitle("Notifications")
        .notificationUndoBanner(playlists: playlistsByID)
        .task { await notifications.updateAuthorization() }
        .onChange(of: scenePhase) { _, phase in
            // Back from the iOS Settings.
            if phase == .active { Task { await notifications.updateAuthorization() } }
        }
        .onDisappear { notifications.dismissUndo() }
    }

    private func groupSection(
        _ group: NotificationGroup, podcasts: [PodcastID: Podcast], playlists: [PlaylistID: Playlist]
    ) -> some View {
        Section {
            Toggle(isOn: Binding(get: { group.state == .on }, set: { isOn in
                save { try notifications.setNotificationsEnabled(isOn, for: group.id) }
            })) {
                VStack(alignment: .leading, spacing: 2) {
                    NotificationGroupLabel(group: group.id, playlists: playlists)
                        .fontWeight(.semibold)
                    if case .mixed(let on, let count) = group.state {
                        Text("\(on) of \(count) on")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .accessibilityIdentifier("notificationGroupToggle")
            ForEach(group.podcasts, id: \.self) { id in
                if let podcast = podcasts[id] {
                    Toggle(isOn: Binding(get: { podcast.notificationsEnabled }, set: { isOn in
                        save { try notifications.setNotificationsEnabled(isOn, for: podcast) }
                    })) {
                        Label {
                            Text(podcast.title).lineLimit(2)
                        } icon: {
                            ArtworkView(url: podcast.artworkURL, cornerRadius: 4)
                                .frame(width: 32, height: 32)
                                .accessibilityHidden(true)
                        }
                        .padding(.leading, 16)
                    }
                    .accessibilityIdentifier("notifications.\(podcast.title)")
                }
            }
        }
        .disabled(!notifications.isEnabled)
    }

    private func save(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            Logger.library.error("Saving notifications failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// A playlist with its color and symbol, or "Ohne Playlist".
private struct NotificationGroupLabel: View {
    let group: NotificationGroupID
    let playlists: [PlaylistID: Playlist]

    var body: some View {
        switch group {
        case .playlist(let id):
            if let playlist = playlists[id] { PlaylistLabel(playlist: playlist) }
        case .withoutPlaylist:
            Label("No Playlist", systemImage: "tag.slash")
        }
    }
}

private extension View {
    /// "Mitteilungen für „Sport“ aus · Rückgängig" after the main switch or a group's switch
    /// (N87), also for the system's undo (shake). The sheet covers the root's banner, so the
    /// screen shows its own.
    func notificationUndoBanner(playlists: [PlaylistID: Playlist]) -> some View {
        modifier(NotificationUndoBannerModifier(playlists: playlists))
    }
}

private struct NotificationUndoBannerModifier: ViewModifier {
    let playlists: [PlaylistID: Playlist]
    @Environment(NotificationScheduler.self) private var notifications
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityVoiceOverEnabled) private var isVoiceOverRunning

    /// Longer with VoiceOver, so the banner can still be reached after the announcement.
    private var duration: Duration { isVoiceOverRunning ? .seconds(30) : .seconds(6) }

    func body(content: Content) -> some View {
        content
            // At the bottom: on top it would cover the main switch.
            .overlay(alignment: .bottom) {
                if let change = notifications.undoableChange {
                    UndoBannerLabel(symbolName: change.isOn ? "bell" : "bell.slash", message: message(for: change)) {
                        undoManager?.removeAllActions(withTarget: notifications)
                        undo()
                    }
                    .padding(.horizontal)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: change.id) {
                        try? await Task.sleep(for: duration)
                        if notifications.undoableChange?.id == change.id { notifications.dismissUndo() }
                    }
                }
            }
            .animation(.default, value: notifications.undoableChange?.id)
            .onChange(of: notifications.undoableChange?.id) { _, _ in
                guard let undoManager else { return }
                // The banner went away or a new change came: the former one is no longer undoable.
                undoManager.removeAllActions(withTarget: notifications)
                guard let change = notifications.undoableChange else { return }
                undoManager.registerUndo(withTarget: notifications) { scheduler in
                    MainActor.assumeIsolated {
                        if scheduler.undoableChange?.id == change.id { try? scheduler.undo() }
                    }
                }
                undoManager.setActionName(message(for: change))
            }
    }

    private func undo() {
        do {
            try notifications.undo()
        } catch {
            Logger.library.error("Undoing notifications failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func message(for change: NotificationUndoableChange) -> String {
        switch change.kind {
        case .all:
            return change.isOn ? String(localized: "Notifications on again") : String(localized: "All notifications paused")
        case .group(let group):
            let name = switch group {
            case .playlist(let id): playlists[id]?.displayName ?? ""
            case .withoutPlaylist: String(localized: "No Playlist")
            }
            return change.isOn
                ? String(localized: "Notifications for “\(name)” on")
                : String(localized: "Notifications for “\(name)” off")
        }
    }
}
