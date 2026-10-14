import PodlistKit
import SwiftUI

/// The chapters of the episode in the player (concept §6.6, area "Kapitel"); a tap jumps there.
struct ChaptersView: View {
    @Environment(PlayerController.self) private var player

    var body: some View {
        List {
            ChapterList(chapters: player.chapters, currentIndex: player.chapterContext.index) { chapter in
                player.seek(to: chapter.start)
                if !player.isPlaying { player.resume() }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Chapters")
        .navigationBarTitleDisplayMode(.inline)
    }
}
