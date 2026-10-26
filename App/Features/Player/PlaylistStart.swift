import PodlistKit
import SwiftData
import SwiftUI

/// Starts a playlist, optionally from an episode ("Playlist ab hier"), everywhere a playlist
/// starts (A53): a tap replaces Up Next with "Rückgängig" or, with the setting "Fragen", asks
/// at the button (N24); a long press offers Ersetzen · Nach der aktuellen Folge · Ans Ende
/// (concept §4.4, N43). On an empty Up Next every way simply starts the playlist. For a
/// playlist that runs (the running episode is in it, N107; without an episode) the tap is
/// Pause/Weiter instead (N51), the long press still offers the three ways (rows 4e, 19).
/// Whether the playlist runs the caller knows from its overview or `split`, once per screen.
struct PlaylistStartButton<Label: View>: View {
    let playlist: Playlist
    var episode: Episode?
    var isRunning = false
    @ViewBuilder let label: (_ isRunning: Bool, _ isPlaying: Bool) -> Label

    @Environment(UpNextService.self) private var upNext
    @Environment(PlayerController.self) private var player
    @AppStorage(PlaylistStartPreference.storageKey) private var preference = PlaylistStartPreference.replace
    @State private var isAsking = false

    var body: some View {
        if isRunning && episode == nil {
            Menu {
                ways
            } label: {
                label(true, player.isPlaying)
            } primaryAction: {
                player.togglePlayPause()
            }
        } else {
            Menu {
                ways
            } label: {
                label(false, false)
            } primaryAction: {
                switch upNext.startAction(preference: preference) {
                case .askUser: isAsking = true
                case .playNow: upNext.playNow(playlist, from: episode)
                }
            }
            .confirmationDialog("The queue is not empty", isPresented: $isAsking, titleVisibility: .visible) {
                ways
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Replacing the queue can be undone.")
            }
        }
    }

    @ViewBuilder private var ways: some View {
        Button("Replace Queue", systemImage: "play.fill") { upNext.playNow(playlist, from: episode) }
            .accessibilityIdentifier("startReplace")
        Button("Play After Current Episode", systemImage: "text.line.first.and.arrowtriangle.forward") {
            upNext.playAfterCurrent(playlist, from: episode)
        }
            .accessibilityIdentifier("startAfterCurrent")
        Button("Add to End of Queue", systemImage: "text.line.last.and.arrowtriangle.forward") {
            upNext.append(playlist, from: episode)
        }
            .accessibilityIdentifier("startAppend")
    }
}
