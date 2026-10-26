import PodlistKit
import SwiftUI
import UIKit

/// Podcast, episode or chapter artwork with a placeholder; decorative for VoiceOver.
/// Chapter images embedded in audio files come from the `ChapterImageStore` (N29).
/// Loads through `URLCache.shared` and retries whenever the view appears again (unlike
/// `AsyncImage`, which keeps showing its failure after a cancelled load). Decoded thumbnails
/// stay in `ArtworkCache`, so a row that scrolls back in shows its artwork in its first frame.
struct ArtworkView: View {
    let url: URL?
    var cornerRadius: CGFloat = 8
    @State private var image: UIImage?
    @State private var loadedURL: URL?
    @State private var loadedSide: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            let side = (proxy.size.width * displayScale).rounded()
            ZStack {
                if let image = image ?? url.flatMap({ ArtworkCache.image(for: $0, side: side) }) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(.quaternary)
                    Image(systemName: "mic.fill")
                        .font(.title)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .task(id: LoadRequest(url: url, side: side)) {
                await load(side: side)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }

    private func load(side: CGFloat) async {
        guard side > 0, url != loadedURL || image == nil || side > loadedSide else { return }
        if url != loadedURL { image = nil }
        guard let url else { return }
        if let cached = ArtworkCache.image(for: url, side: side) {
            image = cached
            loadedURL = url
            loadedSide = side
            return
        }
        guard let data = await ChapterImageStore.shared.imageData(for: url),
              let loaded = await Self.thumbnail(from: data, side: side),
              // A load for an earlier URL that finishes late must not replace the new image.
              !Task.isCancelled, url == self.url else { return }
        ArtworkCache.store(loaded, for: url, side: side)
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

/// Decoded thumbnails of this app run, by URL and pixel size. `URLCache` keeps the encoded
/// files; decoding a 3000 × 3000 px cover again for every row that scrolls in is what made
/// lists stutter. Bounded by memory cost, so iOS keeps the rest under control.
enum ArtworkCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = 40_000_000
        return cache
    }()

    static func image(for url: URL, side: CGFloat) -> UIImage? {
        cache.object(forKey: key(url, side))
    }

    static func store(_ image: UIImage, for url: URL, side: CGFloat) {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        cache.setObject(image, forKey: key(url, side), cost: Int(pixels * 4))
    }

    private static func key(_ url: URL, _ side: CGFloat) -> NSString {
        "\(Int(side))|\(url.absoluteString)" as NSString
    }
}
