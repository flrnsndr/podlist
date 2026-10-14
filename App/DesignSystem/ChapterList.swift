import PodlistKit
import SwiftUI

/// The chapters of an episode (concept §4.6): start time, title, image and link; hidden
/// chapters (JSON `toc: false`) are not listed. Tapping a row calls `onSelect`.
struct ChapterList: View {
    let chapters: [Chapter]
    /// Index into the visible chapters that is playing now, if any.
    var currentIndex: Int?
    let onSelect: (Chapter) -> Void

    var body: some View {
        ForEach(Array(ChapterSelection.visible(chapters).enumerated()), id: \.offset) { index, chapter in
            ChapterRow(chapter: chapter, number: index + 1, isCurrent: index == currentIndex) { onSelect(chapter) }
        }
    }
}

private struct ChapterRow: View {
    let chapter: Chapter
    let number: Int
    let isCurrent: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    if let image = chapter.imageURL {
                        ArtworkView(url: image, cornerRadius: 4)
                            .frame(width: 40)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(isCurrent ? .body.bold() : .body)
                            .multilineTextAlignment(.leading)
                        Text(chapter.start.clockText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if isCurrent {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("\(title), \(chapter.start.clockText)"))
            .accessibilityValue(isCurrent ? Text("Playing") : Text(verbatim: ""))
            .accessibilityHint(Text("Plays from this chapter"))
            .accessibilityIdentifier("chapterRow")
            if let link = chapter.linkURL {
                Link(destination: link) {
                    Image(systemName: "link")
                }
                .accessibilityLabel(Text("Open Chapter Link"))
            }
        }
    }

    private var title: String {
        chapter.title.isEmpty ? String(localized: "Chapter \(number)") : chapter.title
    }
}
