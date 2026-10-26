import PodlistKit
import SwiftData
import SwiftUI

/// ⏭ in the player sheet (N101): skips the running episode as heard. Next to the symbol the
/// artwork of the episode that plays next; disabled when nothing follows.
struct NextEpisodeButton: View {
    @Environment(PlayerController.self) private var player
    @Environment(UpNextService.self) private var upNext
    /// Read so the button follows every change of Up Next (and every save, see CLAUDE.md).
    @Query private var queueItems: [QueueItem]
    @ScaledMetric(relativeTo: .body) private var artworkSide: CGFloat = 24

    var body: some View {
        let next = queueItems.isEmpty || player.episode == nil ? nil : upNext.episodeAfterSkip()
        Button {
            upNext.skip()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "forward.end.alt.fill")
                if let next {
                    ArtworkView(url: next.imageURL ?? next.podcast?.artworkURL, cornerRadius: 4)
                        .frame(width: artworkSide, height: artworkSide)
                }
            }
        }
        .disabled(next == nil)
        .accessibilityLabel(accessibilityLabel(next))
        .accessibilityIdentifier("nextEpisodeButton")
    }

    private func accessibilityLabel(_ next: Episode?) -> Text {
        guard let next else { return Text("Next Episode") }
        guard let podcast = next.podcast?.title else { return Text("Next Episode: \(next.title)") }
        return Text("Next Episode: \(podcast) – \(next.title)")
    }
}
