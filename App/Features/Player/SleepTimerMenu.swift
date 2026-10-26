import PodlistKit
import SwiftUI

/// Sleep timer in the player (A27): minutes, end of chapter, end of episode (N27). Off, only
/// its icon; running, the icon and what is left.
struct SleepTimerMenu: View {
    @Environment(PlayerController.self) private var player

    static let minutes = [5, 10, 15, 30, 45, 60]

    var body: some View {
        Menu {
            if player.sleepTimer != nil {
                Button("Turn Off Sleep Timer", systemImage: "moon.zzz", role: .destructive) { player.setSleepTimer(nil) }
            }
            Section("Sleep Timer") {
                ForEach(Self.minutes, id: \.self) { minutes in
                    Button(TimeInterval(minutes * 60).durationText) {
                        player.setSleepTimer(.duration(TimeInterval(minutes * 60)))
                    }
                }
                if player.hasChapters {
                    Button("End of Chapter") { player.setSleepTimer(.endOfChapter) }
                }
                Button("End of Episode") { player.setSleepTimer(.endOfEpisode) }
                    .accessibilityIdentifier("sleepTimerEndOfEpisode")
            }
        } label: {
            if player.sleepTimer != nil {
                Label {
                    Text(remainingText)
                } icon: {
                    Image(systemName: "moon.zzz.fill")
                }
                .labelStyle(.titleAndIcon)
            } else {
                Label("Sleep Timer", systemImage: "moon.zzz")
                    .labelStyle(.iconOnly)
            }
        }
        .accessibilityIdentifier("sleepTimerButton")
        .accessibilityLabel(player.sleepTimer == nil ? Text("Sleep Timer") : Text("Sleep Timer: \(remainingText)"))
    }

    private var remainingText: String {
        switch player.sleepTimer?.mode {
        case .endOfChapter: String(localized: "End of Chapter")
        case .endOfEpisode: String(localized: "End of Episode")
        default: (player.sleepTimerSecondsLeft ?? 0).clockText
        }
    }
}
