import PodlistKit
import SwiftUI

/// The download state of an episode as a small symbol (concept §4.7: every row shows it);
/// nothing when it is not loaded.
struct DownloadStatusIcon: View {
    let episode: Episode
    @Environment(DownloadService.self) private var downloads

    var body: some View {
        switch episode.downloadState {
        case .none:
            EmptyView()
        case .queued:
            Image(systemName: "arrow.down.circle.dotted")
                .accessibilityLabel(Text("Waiting to download"))
        case .downloading:
            if let fraction = downloads.progress[episode.uuid] ?? nil {
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.mini)
                    .accessibilityLabel(Text("Downloading"))
                    .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel(Text("Downloading"))
            }
        case .downloaded:
            Image(systemName: "arrow.down.circle.fill")
                .accessibilityLabel(Text("Downloaded"))
        case .failed:
            Image(systemName: "exclamationmark.circle")
                .accessibilityLabel(Text("Download failed"))
        }
    }
}

/// Download, retry, cancel or delete, depending on the state (concept §4.7).
struct DownloadButton: View {
    let episode: Episode
    @Environment(DownloadService.self) private var downloads

    var body: some View {
        switch episode.downloadState {
        case .none:
            Button("Download", systemImage: "arrow.down.circle") { downloads.download(episode) }
        case .failed:
            Button("Retry Download", systemImage: "arrow.clockwise") { downloads.download(episode) }
        case .queued, .downloading:
            Button("Cancel Download", systemImage: "xmark.circle", role: .destructive) { downloads.delete([episode]) }
        case .downloaded:
            Button("Delete Download", systemImage: "trash", role: .destructive) { downloads.delete([episode]) }
        }
    }
}

/// One line about the download: size, progress or why it failed.
struct DownloadDetailText: View {
    let episode: Episode
    @Environment(DownloadService.self) private var downloads

    var body: some View {
        Group {
            switch episode.downloadState {
            case .none:
                if let size = episode.fileSize, size > 0 {
                    Text(size, format: .byteCount(style: .file))
                }
            case .queued:
                Text(downloads.isPaused ? "Downloads paused" : "Waiting to download")
            case .downloading:
                if let fraction = downloads.progress[episode.uuid] ?? nil {
                    Text("Downloading: \(fraction.formatted(.percent.precision(.fractionLength(0))))")
                } else {
                    Text("Downloading")
                }
            case .downloaded:
                Text("Downloaded · \((episode.fileSize ?? 0).formatted(.byteCount(style: .file)))")
            case .failed:
                Text(downloads.failures[episode.uuid]?.text ?? "Download failed")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
