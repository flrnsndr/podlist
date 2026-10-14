import UIKit

/// Covers for the made-up podcasts of `-screenshots` (`SampleData.insertScreenshots`): a
/// gradient with a symbol, rendered once per launch into the temporary directory.
enum ScreenshotArtwork {
    static func url(for slug: String) -> URL? {
        guard let style = styles[slug] else { return nil }
        let directory = URL.temporaryDirectory.appending(path: "ScreenshotArtwork", directoryHint: .isDirectory)
        let file = directory.appending(path: "\(slug).png")
        let side: CGFloat = 600
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { context in
            let colors = [style.from.cgColor, style.to.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: side, y: side), options: [])
            }
            let configuration = UIImage.SymbolConfiguration(pointSize: side * 0.38, weight: .semibold)
            guard let symbol = UIImage(systemName: style.symbol, withConfiguration: configuration)?
                .withTintColor(.white.withAlphaComponent(0.92), renderingMode: .alwaysOriginal) else { return }
            let size = symbol.size
            symbol.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try image.pngData()?.write(to: file, options: .atomic)
            return file
        } catch {
            return nil
        }
    }

    private struct Style {
        var from: UIColor
        var to: UIColor
        var symbol: String
    }

    private static let styles: [String: Style] = [
        "morning": Style(from: .systemOrange, to: .systemRed, symbol: "sunrise.fill"),
        "floor-notes": Style(from: .systemIndigo, to: .systemBlue, symbol: "building.columns.fill"),
        "interjection": Style(from: .systemPurple, to: .systemIndigo, symbol: "megaphone.fill"),
        "market": Style(from: .systemMint, to: .systemTeal, symbol: "chart.line.uptrend.xyaxis"),
        "whistle": Style(from: .systemGreen, to: .systemMint, symbol: "soccerball"),
        "circuit": Style(from: .systemBlue, to: .systemCyan, symbol: "bolt.fill"),
        "long-road": Style(from: .systemBrown, to: .systemOrange, symbol: "map.fill"),
        "observatory": Style(from: .systemIndigo, to: .black, symbol: "moon.stars.fill"),
        "kitchen": Style(from: .systemPink, to: .systemOrange, symbol: "cup.and.saucer.fill"),
        "headwind": Style(from: .systemTeal, to: .systemBlue, symbol: "wind"),
        "odds-and-ends": Style(from: .systemYellow, to: .systemOrange, symbol: "paperclip"),
    ]
}
