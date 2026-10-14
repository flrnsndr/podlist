import PodlistKit
import SwiftUI

/// Settings (concept §6.6): the player (speed, skip intervals, skip buttons on the lock
/// screen, N25/N26/A35), what a tap on ▶ of a playlist does while Up Next is not empty
/// (concept §4.4, N43, A52), downloads with the storage screen (concept §4.7, A43) and
/// notifications per podcast (N35) and, at the bottom, the listening stats (concept §4.11, N62)
/// with the listening history next to it (concept §4.12, N81).
struct SettingsView: View {
    @AppStorage(PlaylistStartPreference.storageKey) private var startPreference = PlaylistStartPreference.replace
    @Environment(PlayerController.self) private var player
    @Environment(DownloadService.self) private var downloads
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var player = player
        @Bindable var downloads = downloads
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $player.globalSpeed, in: PlaybackRules.speedRange, step: PlaybackRules.speedStep) {
                        LabeledContent("Default Speed", value: player.globalSpeed.speedText)
                    }
                    Picker("Skip Back", selection: $player.skipBackwardInterval) {
                        ForEach(PlayerController.skipIntervals, id: \.self) { Text($0.secondsText).tag($0) }
                    }
                    Picker("Skip Forward", selection: $player.skipForwardInterval) {
                        ForEach(PlayerController.skipIntervals, id: \.self) { Text($0.secondsText).tag($0) }
                    }
                    Picker("Lock Screen & Headphones", selection: $player.remoteSkipsChapters) {
                        Text("Skip Seconds").tag(false)
                        Text("Skip Chapters").tag(true)
                    }
                } header: {
                    Text("Player")
                } footer: {
                    Text("Podcasts can have their own speed. With “Skip Chapters”, episodes without chapters skip seconds.")
                }
                Section {
                    Picker("Starting a Playlist", selection: $startPreference) {
                        Text("Replace Queue").tag(PlaylistStartPreference.replace)
                        Text("Ask").tag(PlaylistStartPreference.ask)
                    }
                } header: {
                    Text("Queue")
                } footer: {
                    Text("Applies when the queue is not empty; replacing can be undone. Touch and hold ▶ to play a playlist after the current episode or at the end.")
                }
                Section {
                    NavigationLink {
                        StorageView()
                    } label: {
                        Label("Storage", systemImage: "internaldrive")
                    }
                    Toggle("Delete Played Downloads", isOn: $downloads.deletesPlayed)
                    Toggle("Download over Cellular", isOn: $downloads.allowsCellular)
                    Toggle("Download in Low Data Mode", isOn: $downloads.allowsLowDataMode)
                } header: {
                    Text("Downloads")
                } footer: {
                    Text("Played downloads are deleted once the episode has left the player. Playlists can download their episodes automatically.")
                }
                Section {
                    NavigationLink {
                        NotificationSettingsView()
                    } label: {
                        Label("Notifications", systemImage: "bell.badge")
                    }
                    .accessibilityIdentifier("notificationSettings")
                }
                Section {
                    NavigationLink {
                        ListeningStatsView()
                    } label: {
                        Label("Listening Stats", systemImage: "chart.bar.xaxis")
                    }
                    .accessibilityIdentifier("listeningStats")
                    NavigationLink {
                        ListeningHistoryView()
                    } label: {
                        Label("Listening History", systemImage: "clock.arrow.circlepath")
                    }
                    .accessibilityIdentifier("listeningHistory")
                } footer: {
                    Text("Recorded on this device only, while you listen.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
