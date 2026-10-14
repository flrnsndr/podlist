import PodlistKit
import SwiftData
import SwiftUI

/// Starts a playlist, optionally from an episode ("Playlist ab hier"), everywhere a playlist
/// starts (A53): a tap replaces Up Next with "Rückgängig" or, with the setting "Fragen", asks
/// at the button (N24); a long press offers Ersetzen · Nach der aktuellen Folge · Ans Ende
/// (concept §4.4, N43). On an empty Up Next every way simply starts the playlist. For the
/// running playlist (without an episode) the button is Pause/Weiter instead (N51).
struct PlaylistStartButton<Label: View>: View {
    let playlist: Playlist
    var episode: Episode?
    @ViewBuilder let label: (_ isRunning: Bool, _ isPlaying: Bool) -> Label

    @Environment(UpNextService.self) private var upNext
    @Environment(PlayerController.self) private var player
    @AppStorage(PlaylistStartPreference.storageKey) private var preference = PlaylistStartPreference.replace
    @Query(filter: #Predicate<QueueItem> { $0.isNowPlaying }) private var nowPlaying: [QueueItem]
    @State private var isAsking = false

    private var isRunning: Bool {
        episode == nil && nowPlaying.first?.playlist == playlist
    }

    var body: some View {
        if isRunning {
            Button {
                player.togglePlayPause()
            } label: {
                label(true, player.isPlaying)
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
