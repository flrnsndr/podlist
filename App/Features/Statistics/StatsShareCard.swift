import CoreTransferable
import PodlistKit
import SwiftUI
import UniformTypeIdentifiers

/// Share as an image (plan-hoerstatistik §8): a card of its own in story format 9:16,
/// always light on dark, previewed in a sheet and shared as PNG.
struct StatsShareSheet: View {
    let report: StatsReport
    let lookup: StatsLookup
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @State private var image: StatsShareImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let image {
                    Image(uiImage: image.preview)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: 20))
                        .shadow(radius: 12)
                        .accessibilityLabel(Text("Share Card"))
                        .accessibilityIdentifier("statsShareCard")
                    ShareLink(
                        item: image,
                        preview: SharePreview(report.period.shareTitle(in: calendar), image: Image(uiImage: image.preview))
                    ) {
                        Label("Share Image", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding()
            .navigationTitle("Share")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await render() }
    }

    /// `ImageRenderer` does not wait for loading images, so covers come first (plan §8): in
    /// parallel and for at most a few seconds; a missing cover shows the playlist's symbol.
    private func render() async {
        let requests = report.topPodcasts.prefix(5).compactMap { share in
            lookup.artworkURL(of: share.podcast).map { (share.podcast, $0) }
        }
        let covers = await withTaskGroup(of: (PodcastRef, UIImage?).self) { group in
            for (podcast, url) in requests {
                group.addTask { (podcast, await Self.cover(from: url)) }
            }
            var covers: [PodcastRef: UIImage] = [:]
            for await (podcast, image) in group { covers[podcast] = image }
            return covers
        }
        let card = StatsShareCard(report: report, lookup: lookup, covers: covers)
            .environment(\.calendar, calendar)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        renderer.proposedSize = ProposedViewSize(StatsShareCard.size)
        guard let uiImage = renderer.uiImage, let data = uiImage.pngData() else { return }
        image = StatsShareImage(data: data, preview: uiImage, name: report.period.shareTitle(in: calendar))
    }
}

extension StatsShareSheet {
    nonisolated private static func cover(from url: URL) async -> UIImage? {
        await withTaskGroup(of: UIImage?.self) { group in
            group.addTask {
                guard let data = await ChapterImageStore.shared.imageData(for: url) else { return nil }
                return UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 240, height: 240))
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(3))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

/// The rendered card as a PNG for `ShareLink`.
struct StatsShareImage: Transferable {
    let data: Data
    let preview: UIImage
    let name: String

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.data }
            .suggestedFileName { "\($0.name).png" }
    }
}

/// 360 × 640 pt, rendered at 3× = 1080 × 1920 px.
struct StatsShareCard: View {
    static let size = CGSize(width: 360, height: 640)

    let report: StatsReport
    let lookup: StatsLookup
    let covers: [PodcastRef: UIImage]
    @Environment(\.calendar) private var calendar

    var body: some View {
        ZStack {
            background
            VStack(alignment: .leading, spacing: 18) {
                Text(report.period.shareTitle(in: calendar))
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                if let total = report.totalTime {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(total.listenedSeconds.durationText)
                            .font(.system(size: 44, weight: .heavy, design: .rounded))
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        if let conversion = report.conversion {
                            Text(conversion.sentence)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .opacity(0.85)
                                .lineLimit(2)
                        }
                    }
                }
                if let profile = report.listenerProfile {
                    Label(profile.title, systemImage: profile.symbolName)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.18), in: .capsule)
                }
                topFive
                Spacer(minLength: 0)
                facts
                HStack {
                    Spacer()
                    Text(verbatim: "Podlist")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .opacity(0.7)
                }
            }
            .padding(28)
            .foregroundStyle(.white)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    // MARK: Parts

    private var background: some View {
        // Real playlists only: "Ohne Playlist" would make the card grey.
        let colors = report.playlistShares.filter { $0.playlist != nil }.prefix(3).map { lookup.color(of: $0.playlist) }
        let stops = colors.isEmpty ? [Color.indigo, Color.purple] : (colors.count == 1 ? [colors[0], .black] : colors)
        return ZStack {
            Color.black
            LinearGradient(colors: stops.map { $0.opacity(0.85) }, startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
            if let heatmap = report.heatmap { texture(heatmap) }
        }
    }

    /// The listening pattern as a faint dot texture.
    private func texture(_ heatmap: Heatmap) -> some View {
        let maximum = max(heatmap.seconds.flatMap(\.self).max() ?? 1, 1)
        return VStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { day in
                HStack(spacing: 6) {
                    ForEach(0..<24, id: \.self) { hour in
                        Circle()
                            .fill(.white.opacity(0.03 + 0.17 * heatmap.seconds[day][hour] / maximum))
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        .rotationEffect(.degrees(-12))
        .offset(x: 40, y: 150)
    }

    @ViewBuilder
    private var topFive: some View {
        let top = Array(report.topPodcasts.prefix(5))
        if !top.isEmpty {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    ForEach(Array(top.prefix(3).enumerated().reversed()), id: \.offset) { index, share in
                        cover(for: share.podcast)
                            .frame(width: 96 - CGFloat(index) * 10, height: 96 - CGFloat(index) * 10)
                            .rotationEffect(.degrees(Double(index) * 9 - 4))
                            .offset(x: CGFloat(index) * 18, y: CGFloat(index) * 6)
                            .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                    }
                }
                .frame(width: 120, height: 110, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Top 5")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .opacity(0.7)
                    ForEach(Array(top.enumerated()), id: \.offset) { index, share in
                        Text(verbatim: "\(index + 1)  \(share.podcast.title)")
                            .font(.system(size: 14, weight: index == 0 ? .bold : .medium, design: .rounded))
                            .lineLimit(1)
                    }
                }
            }
        }
    }

    private func cover(for podcast: PodcastRef) -> some View {
        Group {
            if let image = covers[podcast] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                let playlist = lookup.playlist(of: podcast)
                ZStack {
                    Rectangle().fill(lookup.color(of: playlist).gradient)
                    Image(systemName: lookup.symbol(of: playlist)).font(.title.bold())
                }
            }
        }
        .clipShape(.rect(cornerRadius: 10))
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let favorite = report.favoritePlaylist {
                fact(symbol: lookup.symbol(of: favorite.playlist), title: String(localized: "Favorite Playlist"),
                     value: "\(lookup.name(of: favorite.playlist)) · \(favorite.share.percentText)")
            }
            if let record = report.recordDay {
                fact(symbol: "medal.fill", title: String(localized: "Record Day"),
                     value: "\(record.day.shortDayText) · \(record.seconds.durationText)")
            }
            if let streak = report.streak {
                fact(symbol: "flame.fill", title: String(localized: "Longest Streak"), value: TimeInterval.daysText(streak.longest))
            }
        }
    }

    private func fact(symbol: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.18), in: .rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 11, weight: .heavy, design: .rounded)).opacity(0.7)
                Text(value).font(.system(size: 15, weight: .bold, design: .rounded)).lineLimit(1)
            }
        }
    }
}

extension StatsPeriod {
    /// "October 2026" / "My Podcast Year 2026".
    func shareTitle(in calendar: Calendar) -> String {
        switch self {
        case .month: title(in: calendar)
        case let .year(year): String(localized: "My Podcast Year \(String(year))")
        }
    }
}

/// The insights the share card picks from the report.
extension StatsReport {
    var totalTime: TotalTime? {
        insights.lazy.compactMap { if case let .totalTime(value) = $0 { value } else { nil } }.first
    }

    var conversion: Conversion? {
        insights.lazy.compactMap { if case let .conversion(value) = $0 { value } else { nil } }.first
    }

    var listenerProfile: ListenerProfile? {
        insights.lazy.compactMap { if case let .listenerType(value) = $0 { value } else { nil } }.first
    }

    var topPodcasts: [PodcastShare] {
        insights.lazy.compactMap { if case let .topPodcasts(value) = $0 { value } else { nil } }.first ?? []
    }

    var favoritePlaylist: PlaylistShare? {
        insights.lazy.compactMap { if case let .playlists(favorite, _) = $0 { favorite } else { nil } }.first
    }

    var playlistShares: [PlaylistShare] {
        insights.lazy.compactMap { if case let .playlists(_, all) = $0 { all } else { nil } }.first ?? []
    }

    var recordDay: RecordDay? {
        insights.lazy.compactMap { if case let .recordDay(value) = $0 { value } else { nil } }.first
    }

    var streak: Streak? {
        insights.lazy.compactMap { if case let .streak(value) = $0 { value } else { nil } }.first
    }

    var heatmap: Heatmap? {
        insights.lazy.compactMap { if case let .heatmap(value) = $0 { value } else { nil } }.first
    }
}
