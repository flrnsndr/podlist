import PodlistKit
import SwiftUI

/// Playback speed in the player (N25): changes the speed in effect, the podcast's own if it
/// has one, else the global one; "Nur für diesen Podcast" switches between them.
struct SpeedView: View {
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss

    static let presets: [Double] = [0.8, 1.0, 1.2, 1.5, 1.8, 2.0]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: Binding(get: { player.speed }, set: { player.setSpeed($0) }),
                            in: PlaybackRules.speedRange, step: PlaybackRules.speedStep) {
                        Text(player.speed.speedText)
                            .font(.title2.monospacedDigit().bold())
                    }
                    .accessibilityIdentifier("speedStepper")
                    HStack {
                        ForEach(Self.presets, id: \.self) { preset in
                            Button(preset.speedText) { player.setSpeed(preset) }
                                .buttonStyle(.bordered)
                                .tint(abs(player.speed - preset) < 0.01 ? .accentColor : .secondary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .font(.footnote.monospacedDigit())
                    .controlSize(.small)
                }
                if let podcast = player.episode?.podcast {
                    Section {
                        Toggle("Only for This Podcast", isOn: Binding(
                            get: { player.usesPodcastSpeed }, set: { player.setUsesPodcastSpeed($0) }))
                            .accessibilityIdentifier("podcastSpeedToggle")
                    } footer: {
                        Text("\(podcast.title) plays at its own speed; all other podcasts use the default speed.")
                    }
                }
            }
            .navigationTitle("Playback Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
