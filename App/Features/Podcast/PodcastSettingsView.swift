import PodlistKit
import SwiftUI
import os

/// Settings of one podcast (concept §2, §5): notifications (N35, N87), its own speed (N25),
/// skipping the intro (A28) and the outro (N28).
struct PodcastSettingsView: View {
    let podcast: Podcast
    @Environment(LibraryService.self) private var library
    @Environment(NotificationScheduler.self) private var notifications
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    /// Steps for intro and outro, up to 5 minutes.
    private static let skipStep = 5
    private static let skipRange = 0...300

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Notifications", isOn: Binding(
                        get: { podcast.notificationsEnabled },
                        set: { isOn in save { try library.setNotificationsEnabled(isOn, for: podcast) } }))
                        .accessibilityIdentifier("notificationsToggle")
                        .disabled(!notifications.isEnabled)
                } footer: {
                    if notifications.isEnabled {
                        Text("Get a notification when a new episode comes out.")
                    } else {
                        // N87: the main switch pauses all; the podcast keeps its value.
                        Text("All notifications are turned off in the settings.")
                    }
                }
                Section {
                    Toggle("Own Speed", isOn: Binding(
                        get: { podcast.playbackSpeed != nil },
                        set: { isOn in player.setSpeed(isOn ? player.globalSpeed : nil, for: podcast) }))
                        .accessibilityIdentifier("ownSpeedToggle")
                    if let speed = podcast.playbackSpeed {
                        Stepper(value: Binding(get: { speed }, set: { player.setSpeed($0, for: podcast) }),
                                in: PlaybackRules.speedRange, step: PlaybackRules.speedStep) {
                            LabeledContent("Speed", value: speed.speedText)
                        }
                    }
                } footer: {
                    Text("Without its own speed, the podcast plays at the default speed (\(player.globalSpeed.speedText)).")
                }
                Section {
                    skipStepper("Skip Intro", value: podcast.skipIntroSeconds) { seconds in
                        try library.setSkipIntro(seconds, for: podcast)
                    }
                    .accessibilityIdentifier("skipIntroStepper")
                    skipStepper("Skip Outro", value: podcast.skipOutroSeconds) { seconds in
                        try library.setSkipOutro(seconds, for: podcast)
                    }
                    .accessibilityIdentifier("skipOutroStepper")
                } footer: {
                    Text("Episodes start after the intro. When playback reaches the outro, the episode counts as finished and the next one starts.")
                }
            }
            .navigationTitle("Podcast Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func skipStepper(_ title: LocalizedStringKey, value: Int, set: @escaping (Int) throws -> Void) -> some View {
        Stepper(value: Binding(get: { value }, set: { newValue in save { try set(newValue) } }),
                in: Self.skipRange, step: Self.skipStep) {
            LabeledContent(title) {
                Text(value == 0 ? String(localized: "Off") : TimeInterval(value).secondsText)
            }
        }
    }

    private func save(_ change: () throws -> Void) {
        do {
            try change()
        } catch {
            Logger.library.error("Saving podcast settings failed: \(String(describing: error), privacy: .public)")
        }
    }
}
