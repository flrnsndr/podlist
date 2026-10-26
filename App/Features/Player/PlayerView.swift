import PodlistKit
import SwiftUI

/// Player sheet (concept §6.6): artwork (the chapter image while a chapter has one), the
/// progress bar with chapters as segments, the chapter row (‹ chapter ›, a tap on the title
/// opens the chapters), skip by seconds, play/pause, speed, sleep timer, next episode and
/// chapters (concept §4.6). Below the player, the show notes; their first lines peek above the
/// bottom toolbar, and the sheet snaps between the two (N80, `PlayerPageSnap`).
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
    /// The scroll offset while the sheet is not resting on the notes (for the peek's fade).
    @State private var scrollOffset: CGFloat = 0
    /// How much of the notes peeks above the bottom toolbar: their heading, date and first lines.
    @ScaledMetric(relativeTo: .body) private var scaledPeekHeight: CGFloat = 132
    /// With the largest text sizes, the peek shows little more than the heading; the player needs the room.
    private var peekHeight: CGFloat { min(scaledPeekHeight, 160) }

    private static let notesID = "showNotes"
    /// The peek fades out over this height above the bottom toolbar.
    private static let peekFade: CGFloat = 56

    var body: some View {
        NavigationStack {
            if let episode = player.episode {
                content(episode)
                    .navigationDestination(for: Podcast.self) { PodcastDetailView(podcast: $0) }
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
        let notes = showNotes(of: episode)
        let notesTop = notes == nil ? 0 : page.notesTop(peek: peekHeight)
        return ScrollView {
            VStack(spacing: 0) {
                playerPage(episode)
                    .frame(height: page.visibleHeight > 0 ? (notes == nil ? page.visibleHeight : notesTop) : nil)
                if let notes {
                    PlayerShowNotes(episode: episode, notes: notes)
                        .frame(minHeight: page.visibleHeight, alignment: .top)
                        .overlay(alignment: .top) {
                            if !isShowingNotes { notesPeek }
                        }
                        .id(Self.notesID)
                }
            }
            .offset(y: drag.lag)
            .mask(alignment: .top) {
                if notes != nil && !isShowingNotes { peekMask } else { Color.black }
            }
        }
        .scrollPosition($scrollPosition)
        .scrollTargetBehavior(PlayerNotesSnapBehavior(notesTop: notesTop, maxOffset: page.maxOffset))
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(isShowingNotes ? .automatic : .hidden)
        .onScrollGeometryChange(for: PageMetrics.self, of: PageMetrics.init) { _, metrics in
            page = metrics
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            drag.update(offset: offset, notesTop: notesTop)
            if !isShowingNotes { scrollOffset = offset }
        }
        .onScrollPhaseChange { oldPhase, phase, context in
            let offset = context.geometry.contentOffset.y + context.geometry.contentInsets.top
            if phase == .interacting {
                drag.begin(at: offset, notesTop: notesTop, maxOffset: page.maxOffset)
            } else if oldPhase == .interacting {
                drag.start = nil
                drag.isArmed = false
                withAnimation(.snappy(duration: 0.3)) { drag.lag = 0 }
            }
            if phase == .idle {
                isShowingNotes = notes != nil && offset > notesTop / 2
                scrollOffset = offset
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
                NextEpisodeButton()
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    private func playerPage(_ episode: Episode) -> some View {
        let duration = max(player.duration ?? episode.duration ?? 0, player.currentTime, 1)
        let progress = ChapterProgress(chapters: player.chapters, duration: duration)
        let position = scrubPosition ?? player.currentTime
        return VStack(spacing: 20) {
            ArtworkView(url: player.chapterContext.imageURL ?? episode.imageURL ?? episode.podcast?.artworkURL, cornerRadius: 16)
                .frame(maxWidth: 320)
                .shadow(radius: 8, y: 4)
            VStack(spacing: 4) {
                Text(episode.title)
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                if let podcast = episode.podcast {
                    NavigationLink(value: podcast) {
                        HStack(spacing: 4) {
                            Text(podcast.title)
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("playerPodcastLink")
                }
            }
            if player.didFail {
                Label("The episode could not be loaded.", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            VStack(spacing: 4) {
                scrubber(progress, at: position)
                chapterRow(progress, at: position)
            }
            HStack(spacing: 48) {
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
        }
        .padding()
        // Beyond this, the controls no longer fit on one page; the notes below keep growing.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// The bar and, below it, elapsed and remaining time; while scrubbing, of the scrub position.
    private func scrubber(_ progress: ChapterProgress, at position: TimeInterval) -> some View {
        VStack(spacing: 0) {
            ChapterProgressBar(
                progress: progress, position: position, scrubPosition: $scrubPosition,
                seek: { player.seek(to: $0) },
                skipForward: { player.skipForward() },
                skipBackward: { player.skipBackward() })
            HStack {
                Text(position.clockText)
                Spacer()
                Text(verbatim: "−" + max(0, progress.duration - position).clockText)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
        }
    }

    /// ‹ chapter › (concept §4.6): where the chapter stands, its title and, if it has one, its
    /// link; a tap on the title opens the chapters. ‹ goes to the start of the chapter or the one
    /// before, › to the next one; each is off where it would not move.
    @ViewBuilder private func chapterRow(_ progress: ChapterProgress, at position: TimeInterval) -> some View {
        let chapters = ChapterSelection.visible(player.chapters)
        if !chapters.isEmpty {
            // One segment per visible chapter: the indices match.
            let index = min(progress.index(at: position), chapters.count - 1)
            let title = chapters[index].title
            let left = progress.remaining(at: position).clockText
            let hasPrevious = ChapterSelection.previousStart(before: position, in: player.chapters) < position - 1
            let hasNext = ChapterSelection.nextStart(after: position, in: player.chapters) != nil
            HStack(spacing: 0) {
                chapterButton("chevron.backward", isEnabled: hasPrevious, pulse: player.buttonPulses.previousChapter) {
                    player.previousChapter()
                }
                .accessibilityLabel(Text("Previous Chapter"))
                .accessibilityIdentifier("previousChapterButton")
                HStack(spacing: 8) {
                    NavigationLink {
                        ChaptersView()
                    } label: {
                        VStack(spacing: 2) {
                            Text("Chapter \(index + 1) of \(chapters.count) · \(left) left")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.tint)
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                        }
                        .multilineTextAlignment(.center)
                        .frame(minHeight: 44)
                        .contentShape(.rect)
                    }
                    .accessibilityLabel(Text("Chapter: \(title)"))
                    .accessibilityValue(Text("Chapter \(index + 1) of \(chapters.count) · \(left) left"))
                    .accessibilityHint(Text("Shows the chapters"))
                    .accessibilityIdentifier("currentChapterTitle")
                    if let link = player.chapterContext.linkURL {
                        Link(destination: link) {
                            Image(systemName: "link")
                                .font(.subheadline.weight(.semibold))
                                .frame(minWidth: 32, minHeight: 44)
                                .contentShape(.rect)
                        }
                        .accessibilityLabel(Text("Open Chapter Link"))
                    }
                }
                .frame(maxWidth: .infinity)
                chapterButton("chevron.forward", isEnabled: hasNext, pulse: player.buttonPulses.nextChapter) {
                    player.nextChapter()
                }
                .accessibilityLabel(Text("Next Chapter"))
                .accessibilityIdentifier("nextChapterButton")
            }
            .buttonStyle(.plain)
        }
    }

    private func chapterButton(_ symbol: String, isEnabled: Bool, pulse: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
                .symbolEffect(.bounce, value: pulse)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .disabled(!isEnabled)
    }

    /// Over the peeking notes while the sheet rests on the player: a tap scrolls to them.
    private var notesPeek: some View {
        Button {
            withAnimation { scrollPosition.scrollTo(id: Self.notesID, anchor: .top) }
        } label: {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: peekHeight)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Episode Notes"))
        .accessibilityHint(Text("Shows the episode notes"))
        .accessibilityIdentifier("showNotesPeek")
    }

    /// Fades the peeking notes out above the bottom toolbar and hides what lies below, so nothing
    /// shows through the toolbar; off while the sheet rests on the notes. It masks the content in
    /// its layout frame (outside the drag lag), so the cut stays at the bottom of the visible area.
    private var peekMask: some View {
        VStack(spacing: 0) {
            Color.black.frame(height: max(0, scrollOffset + page.visibleHeight - Self.peekFade))
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: Self.peekFade)
        }
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

/// The player fills the visible area between the bars except for the peek of the notes at its
/// bottom, right above the toolbar. The notes are at least as tall as the visible area: a
/// scroll target goes at most to content height minus container height, and the notes must
/// reach the top. (`containerSize` is the area inside the insets.)
private struct PageMetrics: Equatable {
    var visibleHeight: CGFloat = 0
    var bottomInset: CGFloat = 0
    /// The furthest the content scrolls (offset plus top inset); beyond it, the rubber band.
    var maxOffset: CGFloat = 0

    /// Where the notes start (the height of the player page): `peek` above the bottom toolbar.
    func notesTop(peek: CGFloat) -> CGFloat { max(0, visibleHeight - peek) }

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
