import Charts
import PodlistKit
import SwiftData
import SwiftUI

/// Speicher (concept §4.7, N100): one block with the used space split into unplayed, played
/// and free, the warnings and "Gespielte löschen"; running downloads with pause; the downloads
/// by podcast as a table (N91). Deleting single episodes happens in a podcast's downloads.
/// Warns below 1 GB free (N33).
struct StorageView: View {
    @Query(filter: StorageView.hasDownload, sort: \Episode.publishedAt, order: .reverse)
    private var episodes: [Episode]
    @Environment(DownloadService.self) private var downloads
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var podcastSort = PodcastStorageSort.size
    @State private var isConfirmingDeletePlayed = false

    private static let hasDownload: Predicate<Episode> = {
        let none = DownloadState.none.rawValue
        return #Predicate<Episode> { $0.downloadStateRaw != none }
    }()

    private var downloaded: [Episode] { episodes.filter { $0.downloadState == .downloaded } }
    private var inProgress: [Episode] { episodes.filter { $0.downloadState != .downloaded } }

    private var summary: StorageSummary {
        DownloadRules.summary(downloaded.map { episode in
            DownloadedEpisode(
                episode: episode.episodeID, podcast: PodcastID(episode.podcast?.uuid ?? UUID()),
                podcastTitle: episode.podcast?.title ?? "", bytes: episode.fileSize ?? 0, isPlayed: episode.isPlayed)
        })
    }

    private var artworkURLs: [UUID: URL] {
        var urls: [UUID: URL] = [:]
        for episode in downloaded {
            if let podcast = episode.podcast, let url = podcast.artworkURL { urls[podcast.uuid] = url }
        }
        return urls
    }

    var body: some View {
        let summary = summary
        List {
            overviewSection(summary)
            if !inProgress.isEmpty { inProgressSection }
            podcastSection(summary)
        }
        .navigationTitle("Storage")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete the downloads of \(summary.playedCount) played episodes?",
                            isPresented: $isConfirmingDeletePlayed, titleVisibility: .visible) {
            Button("Delete Played", role: .destructive) { downloads.deleteAllPlayed() }
        }
        .task { downloads.refreshCapacity() }
    }

    // MARK: Sections

    /// Used and free space, unplayed and played in the bar and its legend, the warnings, and
    /// "Gespielte löschen", which removes the played part (only there when something is played).
    private func overviewSection(_ summary: StorageSummary) -> some View {
        Section {
            usage(summary)
            if downloads.isLowOnStorage {
                Label("Less than \(DownloadRules.lowStorageThreshold.formatted(.byteCount(style: .file))) free. Automatic downloads are paused until there is more space.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            if downloads.isPaused && inProgress.isEmpty {
                // A39: the pause stays until "Fortsetzen", also when nothing is waiting.
                HStack {
                    Label("Downloads paused", systemImage: "pause.circle")
                    Spacer()
                    Button("Resume", systemImage: "play.fill") { downloads.resume() }
                        .buttonStyle(.borderless)
                }
            }
            if summary.playedCount > 0 {
                Button(role: .destructive) {
                    isConfirmingDeletePlayed = true
                } label: {
                    // The row would tint the icon with the accent color; it is only there when enabled.
                    Label("Delete Played", systemImage: "trash")
                        .foregroundStyle(.red)
                }
                .accessibilityIdentifier("deleteAllPlayed")
            }
        }
    }

    private func usage(_ summary: StorageSummary) -> some View {
        let free = downloads.availableCapacity
        let legend = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(spacing: 16))
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.totalBytes, format: .byteCount(style: .file))
                    .font(.title2.weight(.semibold))
                    .accessibilityLabel(Text("\(summary.totalBytes.formatted(.byteCount(style: .file))) used by podcasts"))
                Spacer()
                if let free {
                    Text("\(free.formatted(.byteCount(style: .file))) free")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let free {
                StorageBar(unplayed: summary.unplayedBytes, played: summary.playedBytes, free: free)
            }
            legend {
                StorageLegendItem(color: StorageBar.unplayedColor,
                                  text: Text("Unplayed \(summary.unplayedBytes.formatted(.byteCount(style: .file)))"))
                if summary.playedBytes > 0 {
                    StorageLegendItem(color: StorageBar.playedColor,
                                      text: Text("Played \(summary.playedBytes.formatted(.byteCount(style: .file)))"))
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var inProgressSection: some View {
        Section {
            ForEach(inProgress) { episode in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(episode.title).lineLimit(2)
                        DownloadDetailText(episode: episode)
                    }
                    Spacer()
                    DownloadButton(episode: episode)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
            }
        } header: {
            HStack {
                Text("Downloading (\(inProgress.count))")
                Spacer()
                if downloads.isPaused {
                    Button("Resume", systemImage: "play.fill") { downloads.resume() }
                } else {
                    Button("Pause", systemImage: "pause.fill") { Task { await downloads.pause() } }
                }
            }
        }
    }

    private func podcastSection(_ summary: StorageSummary) -> some View {
        let artworkURLs = artworkURLs
        return Section {
            if summary.podcasts.isEmpty {
                Text("No downloaded episodes.")
                    .foregroundStyle(.secondary)
            }
            ForEach(DownloadRules.sorted(summary.podcasts, by: podcastSort), id: \.podcast) { storage in
                NavigationLink {
                    StoragePodcastView(podcastID: storage.podcast.uuid, title: storage.title)
                } label: {
                    StoragePodcastRow(storage: storage, artworkURL: artworkURLs[storage.podcast.uuid])
                }
            }
        } header: {
            HStack(spacing: 4) {
                Text("Downloads")
                if !summary.podcasts.isEmpty {
                    Text(verbatim: "·").accessibilityHidden(true)
                    Text("\(summary.podcasts.count) podcasts")
                }
                Spacer()
                sortMenu
            }
        }
    }

    /// Shows the current sort, so the header says how the list is ordered.
    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $podcastSort) {
                Text("Size").tag(PodcastStorageSort.size)
                Text("Name").tag(PodcastStorageSort.name)
            }
        } label: {
            HStack(spacing: 3) {
                sortName
                Image(systemName: "chevron.down").imageScale(.small)
            }
            .textCase(nil)
        }
        .accessibilityLabel(Text("Sort Podcasts"))
        .accessibilityValue(sortName)
        .accessibilityIdentifier("sortPodcastStorage")
    }

    private var sortName: Text {
        switch podcastSort {
        case .size: Text("Size")
        case .name: Text("Name")
        }
    }
}

/// The downloads of one podcast, with "Alle löschen" (concept §4.7).
struct StoragePodcastView: View {
    let title: String
    @Query private var episodes: [Episode]
    @Environment(DownloadService.self) private var downloads
    @State private var isConfirmingDeleteAll = false

    init(podcastID: UUID, title: String) {
        self.title = title
        let downloaded = DownloadState.downloaded.rawValue
        _episodes = Query(
            filter: #Predicate<Episode> { $0.downloadStateRaw == downloaded && $0.podcast?.uuid == podcastID },
            sort: \Episode.publishedAt, order: .reverse)
    }

    var body: some View {
        List {
            ForEach(episodes) { episode in
                StorageEpisodeRow(episode: episode)
                    .swipeActions {
                        Button("Delete Download", systemImage: "trash", role: .destructive) { downloads.delete([episode]) }
                    }
            }
        }
        .overlay {
            if episodes.isEmpty {
                ContentUnavailableView("No Downloads", systemImage: "arrow.down.circle")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !episodes.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Delete All", systemImage: "trash", role: .destructive) { isConfirmingDeleteAll = true }
                }
            }
        }
        .confirmationDialog("Delete all \(episodes.count) downloads of this podcast?",
                            isPresented: $isConfirmingDeleteAll, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { downloads.delete(episodes) }
        }
    }
}

/// One podcast in the "Downloads" section, laid out like a table: artwork, name, episode count
/// and how many are played on the left, the size right-aligned in its own column (N91, N100).
private struct StoragePodcastRow: View {
    let storage: PodcastStorage
    let artworkURL: URL?
    @ScaledMetric(relativeTo: .body) private var artworkSide: CGFloat = 36

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: artworkURL, cornerRadius: 6)
                .frame(width: artworkSide, height: artworkSide)
                .accessibilityHidden(true)
            StorageSizeRow(bytes: storage.bytes) {
                Text(storage.title)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text("\(storage.episodeCount) episodes")
                    if storage.playedCount > 0 {
                        Text(verbatim: "·").accessibilityHidden(true)
                        Text("\(storage.playedCount) played")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A downloaded episode in its podcast's downloads, in the same table as the podcasts: title
/// and date on the left, the size in its column. Played episodes are dimmed and say "Gespielt".
private struct StorageEpisodeRow: View {
    let episode: Episode

    var body: some View {
        StorageSizeRow(bytes: episode.fileSize ?? 0) {
            Text(episode.title)
                .lineLimit(2)
                .foregroundStyle(episode.isPlayed ? .secondary : .primary)
            HStack(spacing: 4) {
                Text(episode.publishedAt, format: .dateTime.day().month().year())
                if episode.isPlayed {
                    Text(verbatim: "·").accessibilityHidden(true)
                    // Not a `Label`: in a list row it takes the icon column and moves the separator.
                    Image(systemName: "checkmark.circle").accessibilityHidden(true)
                    Text("Played")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A row of the storage tables: the text on the left, the size right-aligned in its own column,
/// so it never wraps under a long name. At accessibility sizes the size goes below the text.
private struct StorageSizeRow<Content: View>: View {
    let bytes: Int64
    @ViewBuilder let content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 2) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(bytes, format: WholeMegabytes())
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }
}

/// Sizes in a column: whole megabytes in every row ("45 MB", "512 MB", "1.230 MB"), so the
/// unit and the precision never change and the right-aligned digits line up. `.byteCount`
/// keeps three significant digits and switches units ("45,3 MB", "1,23 GB").
private struct WholeMegabytes: FormatStyle {
    var locale = Locale.autoupdatingCurrent

    func format(_ bytes: Int64) -> String {
        Measurement(value: Double(bytes), unit: UnitInformationStorage.bytes)
            .converted(to: .megabytes)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided,
                                    numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale))
    }

    func locale(_ locale: Locale) -> WholeMegabytes {
        WholeMegabytes(locale: locale)
    }
}

/// Unplayed, played and free space as one bar (Swift Charts); the numbers are spoken by the
/// text around it.
private struct StorageBar: View {
    static let unplayedColor = Color.accentColor
    static let playedColor = Color.secondary
    let unplayed: Int64
    let played: Int64
    let free: Int64

    var body: some View {
        let unplayedLabel = String(localized: "Unplayed")
        let playedLabel = String(localized: "Played")
        let freeLabel = String(localized: "Free")
        Chart {
            BarMark(x: .value("Bytes", Double(unplayed))).foregroundStyle(by: .value("Kind", unplayedLabel))
            BarMark(x: .value("Bytes", Double(played))).foregroundStyle(by: .value("Kind", playedLabel))
            BarMark(x: .value("Bytes", Double(free))).foregroundStyle(by: .value("Kind", freeLabel))
        }
        .chartForegroundStyleScale([
            unplayedLabel: Self.unplayedColor, playedLabel: Self.playedColor, freeLabel: Color.secondary.opacity(0.25),
        ])
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 12)
        .clipShape(.capsule)
        .accessibilityHidden(true)
    }
}

/// A swatch of the bar's color with its text; the text alone says what it is.
private struct StorageLegendItem: View {
    let color: Color
    let text: Text

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            text
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
