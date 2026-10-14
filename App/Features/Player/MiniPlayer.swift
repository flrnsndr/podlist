import PodlistKit
import SwiftUI

/// Mini-Player in the tab bar accessory (concept §6.6). Tap opens the player. The root view
/// presents the player: SwiftUI may rebuild the accessory whenever the root view changes,
/// which would close a sheet presented from here.
struct MiniPlayer: View {
    let openPlayer: () -> Void
    @Environment(PlayerController.self) private var player

    var body: some View {
        if let episode = player.episode {
            HStack(spacing: 12) {
                Button(action: openPlayer) {
                    HStack(spacing: 10) {
                        ArtworkView(url: player.chapterContext.imageURL ?? episode.imageURL ?? episode.podcast?.artworkURL, cornerRadius: 6)
                            .frame(width: 32)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(episode.title)
                                .font(.subheadline)
                                .lineLimit(1)
                            if let chapter = player.chapterContext.chapter, !chapter.title.isEmpty {
                                Text(chapter.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(episode.title))
                .accessibilityValue(Text(player.chapterContext.chapter?.title ?? ""))
                .accessibilityHint(Text("Opens the player"))
                .accessibilityIdentifier("miniPlayer")

                PlayPauseButton()
                Button { player.skipForward() } label: {
                    Image(systemName: "goforward.\(Int(player.skipForwardInterval))")
                        .symbolEffect(.bounce, value: player.buttonPulses.skipForward)
                }
                .accessibilityLabel(Text("Skip Forward"))
            }
            .padding(.horizontal, 16)
        } else {
            Text("Not Playing")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

struct PlayPauseButton: View {
    @Environment(PlayerController.self) private var player
    var font: Font = .body

    var body: some View {
        Button { player.togglePlayPause() } label: {
            if player.isBuffering {
                ProgressView()
            } else {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(font)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: player.buttonPulses.playPause)
            }
        }
        .accessibilityLabel(player.isPlaying ? Text("Pause") : Text("Play"))
    }
}
