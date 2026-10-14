import PodlistKit
import SwiftUI

/// Player sheet (concept §6.6): artwork (the chapter image while a chapter has one),
/// scrubbing with chapter marks, skip by seconds and by chapter, play/pause, speed, sleep
/// timer, next episode and chapters (concept §4.6). Below the player, the show notes; the
/// sheet snaps between the two (N80, `PlayerPageSnap`).
struct PlayerView: View {
    @Environment(PlayerController.self) private var player
    @Environment(UpNextService.self) private var upNext
    @Environment(\.dismiss) private var dismiss
    @State private var scrubPosition: TimeInterval?
    @State private var isShowingSpeed = false
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var page = PageMetrics()
    /// The sheet rests on the notes (after a snap, not while dragging).
    @State private var isShowingNotes = false
    @State private var drag = PageDrag()

    private static let notesID = "showNotes"

    var body: some View {
        NavigationStack {
            if let episode = player.episode {
                content(episode)
            } else {
                ContentUnavailableView("Not Playing", systemImage: "play.slash")
            }
        }
        .undoBanner()
    }

    /// The episode's show notes, if they say anything.
    private func showNotes(of episode: Episode) -> String? {
        guard let notes = episode.showNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return notes
    }

    private func content(_ episode: Episode) -> some View {
        let hasNotes = showNotes(of: episode) != nil
        return ScrollView {
            VStack(spacing: 0) {
                playerPage(episode, hasNotes: hasNotes)
                    .frame(height: page.visibleHeight > 0 ? page.visibleHeight : nil)
                    .padding(.bottom, hasNotes ? page.bottomInset : 0)
                if let notes = showNotes(of: episode) {
                    PlayerShowNotes(episode: episode, notes: notes)
                        .frame(minHeight: page.visibleHeight, alignment: .top)
                        .id(Self.notesID)
                }
            }
            .offset(y: drag.lag)
        }
        .scrollPosition($scrollPosition)
        .scrollTargetBehavior(PlayerNotesSnapBehavior(notesTop: hasNotes ? page.playerHeight : 0, maxOffset: page.maxOffset))
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(isShowingNotes ? .automatic : .hidden)
        .onScrollGeometryChange(for: PageMetrics.self, of: PageMetrics.init) { _, metrics in
            page = metrics
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            drag.update(offset: offset, notesTop: page.playerHeight)
        }
        .onScrollPhaseChange { oldPhase, phase, context in
            let offset = context.geometry.contentOffset.y + context.geometry.contentInsets.top
            if phase == .interacting {
                drag.begin(at: offset, notesTop: hasNotes ? page.playerHeight : 0, maxOffset: page.maxOffset)
            } else if oldPhase == .interacting {
                drag.start = nil
                drag.isArmed = false
                withAnimation(.snappy(duration: 0.3)) { drag.lag = 0 }
            }
            if phase == .idle {
                isShowingNotes = hasNotes && offset > page.playerHeight / 2
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: drag.isArmed) { _, isArmed in isArmed }
        .onChange(of: episode.uuid) {
            scrollPosition.scrollTo(edge: .top)
            isShowingNotes = false
        }
        .navigationTitle(isShowingNotes ? episode.title : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if player.hasChapters {
                ToolbarItem(placement: .bottomBar) {
                    NavigationLink {
                        ChaptersView()
                    } label: {
                        Label("Chapters", systemImage: "list.number")
                    }
                    .accessibilityIdentifier("chaptersButton")
                }
            }
            ToolbarSpacer(.flexible, placement: .bottomBar)
            ToolbarItem(placement: .bottomBar) {
                Button("Next Episode", systemImage: "forward.end.fill") { upNext.skip() }
                    .accessibilityIdentifier("nextEpisodeButton")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func playerPage(_ episode: Episode, hasNotes: Bool) -> some View {
        VStack(spacing: 24) {
            ArtworkView(url: player.chapterContext.imageURL ?? episode.imageURL ?? episode.podcast?.artworkURL, cornerRadius: 16)
                .frame(maxWidth: 320)
                .shadow(radius: 8, y: 4)
            VStack(spacing: 4) {
                Text(episode.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                if let podcast = episode.podcast {
                    Text(podcast.title).font(.subheadline).foregroundStyle(.secondary)
                }
                currentChapter
            }
            if player.didFail {
                Label("The episode could not be loaded.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            scrubber
            HStack(spacing: player.hasChapters ? 28 : 48) {
                if player.hasChapters {
                    Button { player.previousChapter() } label: {
                        Image(systemName: "backward.end.fill").font(.title3)
                            .symbolEffect(.bounce, value: player.buttonPulses.previousChapter)
                    }
                    .accessibilityLabel(Text("Previous Chapter"))
                }
                Button { player.skipBackward() } label: {
                    Image(systemName: "gobackward.\(Int(player.skipBackwardInterval))").font(.title)
                        .symbolEffect(.bounce, value: player.buttonPulses.skipBackward)
                }
                .accessibilityLabel(Text("Skip Back"))
                PlayPauseButton(font: .system(size: 44))
                    .frame(width: 64, height: 64)
                Button { player.skipForward() } label: {
                    Image(systemName: "goforward.\(Int(player.skipForwardInterval))").font(.title)
                        .symbolEffect(.bounce, value: player.buttonPulses.skipForward)
                }
                .accessibilityLabel(Text("Skip Forward"))
                if player.hasChapters {
                    Button { player.nextChapter() } label: {
                        Image(systemName: "forward.end.fill").font(.title3)
                            .symbolEffect(.bounce, value: player.buttonPulses.nextChapter)
                    }
                    .accessibilityLabel(Text("Next Chapter"))
                    .accessibilityIdentifier("nextChapterButton")
                }
            }
            .buttonStyle(.plain)
            HStack(spacing: 24) {
                Button { isShowingSpeed = true } label: {
                    Text(player.speed.speedText)
                        .font(.body.monospacedDigit().bold())
                        .frame(minWidth: 56)
                }
                .accessibilityLabel(Text("Playback Speed: \(player.speed.speedText)"))
                .accessibilityIdentifier("speedButton")
                SleepTimerMenu()
            }
            .buttonStyle(.bordered)
            .sheet(isPresented: $isShowingSpeed) { SpeedView() }
            Spacer(minLength: 0)
            if hasNotes {
                notesHint
            }
        }
        .padding()
    }

    /// Points to the show notes below; a tap scrolls there.
    private var notesHint: some View {
        Button {
            withAnimation { scrollPosition.scrollTo(id: Self.notesID, anchor: .top) }
        } label: {
            VStack(spacing: 0) {
                Text("Episode Notes").font(.footnote.weight(.semibold))
                Image(systemName: "chevron.compact.down").font(.title2)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("showNotesHint")
    }

    /// The chapter title and, if the chapter has one, its link (concept §4.6).
    @ViewBuilder private var currentChapter: some View {
        if let chapter = player.chapterContext.chapter {
            HStack(spacing: 8) {
                Text(chapter.title)
                    .font(.subheadline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel(Text("Chapter: \(chapter.title)"))
                    .accessibilityIdentifier("currentChapterTitle")
                if let link = player.chapterContext.linkURL {
                    Link(destination: link) {
                        Image(systemName: "link")
                    }
                    .accessibilityLabel(Text("Open Chapter Link"))
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var scrubber: some View {
        let duration = max(player.duration ?? 0, player.currentTime, 1)
        let position = scrubPosition ?? player.currentTime
        VStack(spacing: 4) {
            Slider(
                value: Binding(get: { position }, set: { scrubPosition = $0 }),
                in: 0...duration,
                onEditingChanged: { editing in
                    if !editing, let scrubPosition {
                        player.seek(to: scrubPosition)
                        self.scrubPosition = nil
                    }
                })
                .accessibilityLabel(Text("Position"))
                .accessibilityValue(Text(position.clockText))
                .background(alignment: .bottom) { chapterMarks(duration: duration) }
            HStack {
                Text(position.clockText)
                Spacer()
                Text(verbatim: "−" + max(0, duration - position).clockText)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    /// Small marks under the slider where chapters begin (concept §4.6, segmented progress).
    private func chapterMarks(duration: TimeInterval) -> some View {
        GeometryReader { proxy in
            ForEach(ChapterSelection.visible(player.chapters).dropFirst(), id: \.start) { chapter in
                Capsule()
                    .fill(.secondary)
                    .frame(width: 2, height: 6)
                    .position(x: proxy.size.width * min(1, chapter.start / duration), y: proxy.size.height - 1)
            }
        }
        .frame(height: 8)
        .offset(y: 8)
        .accessibilityHidden(true)
    }
}

/// The show notes below the player (N80); a timestamp jumps there in the running episode.
/// Its own view, so the player's time ticks do not parse the notes again.
private struct PlayerShowNotes: View {
    let episode: Episode
    let notes: String
    @Environment(PlayerController.self) private var player

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Episode Notes")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("showNotesTitle")
            Text(episode.publishedAt, format: .dateTime.day().month().year())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(HTMLText.attributedString(fromHTML: notes))
                .font(.body)
                .textSelection(.enabled)
                .padding(.top, 8)
                .environment(\.openURL, OpenURLAction { url in
                    guard let time = ShowNotesTimestamps.time(from: url) else { return .systemAction }
                    player.seek(to: time)
                    if !player.isPlaying { player.resume() }
                    return .handled
                })
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }
}

/// The player fills the visible area between the bars and reaches on under the bottom toolbar,
/// so the notes start off screen and never show through it. The notes are at least as tall as
/// the visible area: a scroll target goes at most to content height minus container height,
/// and the notes must reach the top. (`containerSize` is the area inside the insets.)
private struct PageMetrics: Equatable {
    var visibleHeight: CGFloat = 0
    var bottomInset: CGFloat = 0
    /// The furthest the content scrolls (offset plus top inset); beyond it, the rubber band.
    var maxOffset: CGFloat = 0

    /// The player page; the notes start here.
    var playerHeight: CGFloat { visibleHeight + bottomInset }

    init() {}

    init(_ geometry: ScrollGeometry) {
        visibleHeight = geometry.containerSize.height
        bottomInset = geometry.contentInsets.bottom
        maxOffset = geometry.contentSize.height - geometry.containerSize.height
    }
}

/// A drag between the player and the notes (N80): the content lags behind the scroll offset
/// (`PlayerPageSnap.resisted`), so it feels sticky; past the threshold it is armed (a haptic
/// tick) and snaps when let go. On release the lag springs back to 0 while the scroll view
/// moves to its target. A drag may catch the last snap on its way or bouncing.
private struct PageDrag {
    /// Where the drag began (`PlayerPageSnap.start`); nil inside the notes.
    var start: CGFloat?
    /// How far the content stays behind the scroll offset.
    var lag: CGFloat = 0
    var isArmed = false

    mutating func begin(at offset: CGFloat, notesTop: CGFloat, maxOffset: CGFloat) {
        let start = PlayerPageSnap.start(offset: offset, maxOffset: maxOffset)
        self.start = PlayerPageSnap.isBetweenPages(start: start, notesTop: notesTop) ? start : nil
    }

    mutating func update(offset: CGFloat, notesTop: CGFloat) {
        guard let start else { return }
        let distance = PlayerPageSnap.distance(offset: offset, start: start, notesTop: notesTop)
        lag = distance - PlayerPageSnap.resisted(distance, pageHeight: notesTop)
        isArmed = PlayerPageSnap.isArmed(offset: offset, start: start, notesTop: notesTop)
    }
}

/// Snaps between the player and its show notes (`PlayerPageSnap`); scrolling inside the notes
/// stays free. Scroll target offsets start at 0 below the navigation bar (content offset plus
/// the top inset).
private struct PlayerNotesSnapBehavior: ScrollTargetBehavior {
    var notesTop: CGFloat
    var maxOffset: CGFloat

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let start = PlayerPageSnap.start(offset: context.originalTarget.rect.minY, maxOffset: maxOffset)
        target.rect.origin.y = PlayerPageSnap.target(projected: target.rect.minY, start: start, notesTop: notesTop)
    }
}
