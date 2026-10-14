import PodlistKit
import SwiftUI
import UIKit

/// Podcast, episode or chapter artwork with a placeholder; decorative for VoiceOver.
/// Chapter images embedded in audio files come from the `ChapterImageStore` (N29).
/// Loads through `URLCache.shared` and retries whenever the view appears again (unlike
/// `AsyncImage`, which keeps showing its failure after a cancelled load).
struct ArtworkView: View {
    let url: URL?
    var cornerRadius: CGFloat = 8
    @State private var image: UIImage?
    @State private var loadedURL: URL?
    @State private var loadedSide: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "mic.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: LoadRequest(url: url, side: (proxy.size.width * displayScale).rounded())) {
                await load(side: (proxy.size.width * displayScale).rounded())
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }

    private func load(side: CGFloat) async {
        guard side > 0, url != loadedURL || image == nil || side > loadedSide else { return }
        if url != loadedURL { image = nil }
        guard let url,
              let data = await ChapterImageStore.shared.imageData(for: url),
              let loaded = await Self.thumbnail(from: data, side: side),
              // A load for an earlier URL that finishes late must not replace the new image.
              !Task.isCancelled, url == self.url else { return }
        image = loaded
        loadedURL = url
        loadedSide = side
    }

    private struct LoadRequest: Hashable {
        var url: URL?
        var side: CGFloat
    }

    /// Feed artwork is often 3000 × 3000 px; decode only what the view needs.
    @concurrent private static func thumbnail(from data: Data, side: CGFloat) async -> UIImage? {
        await UIImage(data: data)?.byPreparingThumbnail(ofSize: CGSize(width: side, height: side))
    }
}
