import PodlistKit
import SwiftData
import SwiftUI

/// Settings → Hörverlauf (concept §4.12): every started episode, one row per episode on the
/// day it last played, newest first. Playlist chips like the library (N84), "Nicht beendet"
/// in the menu (A73), search in titles and short descriptions (N83), "Vor einem Jahr" on top
/// (A75) and a link to the month's statistics above each month (A76).
struct ListeningHistoryView: View {
    /// From the statistics: scroll to the latest day of this period (A76).
    var focus: DateInterval?

    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Query(sort: \Playlist.displayOrder) private var allPlaylists: [Playlist]
    /// Tags only: "Alles" is no tag (concept §4.1).
    private var playlists: [Playlist] { allPlaylists.tags }
    /// Only to notice new listening: the latest session.
    @Query(ListeningHistoryView.latestSession) private var latest: [ListeningSession]
    @State private var service: ListeningHistoryService?
    @State private var filter = PlaylistFilter.all
    @State private var onlyUnfinished = false
    @State private var search = ""
    @State private var days: [HistoryDay] = []
    /// Headings and rows in one flat list, one list row each: the list stays lazy.
    @State private var items: [HistoryItem] = []
    @State private var selectedEpisode: Episode?
    @State private var addingToPlaylist: Episode?
    @State private var didFocus = false
    @State private var statsMonth: HistoryMonth?

    private static var latestSession: FetchDescriptor<ListeningSession> {
        var descriptor = FetchDescriptor<ListeningSession>(sortBy: [SortDescriptor(\.endedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        return descriptor
    }

    private var query: HistoryQuery { HistoryQuery(filter: filter, onlyUnfinished: onlyUnfinished, search: search) }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                PlaylistFilterBar(playlists: playlists, filter: $filter, identifierPrefix: "history")
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                // Headings are rows, not sticky section headers: two of them (month and day)
                // would cover too much of the list.
                ForEach(items) { item in
                    switch item.kind {
                    case .yearAgo:
                        heading {
                            Text("A Year Ago")
                                .font(.title3.bold())
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("historyYearAgo")
                        }
                    case .month(let start):
                        heading { monthHeading(start) }
                    case .day(let day):
                        heading(top: 0) { dayHeading(day) }
                    case .entry(let entry):
                        row(entry)
                    }
                }
                if days.isEmpty, service != nil {
                    emptyState
                        .padding(.top, PlaylistFilterBar.emptyStateGap)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .accessibilityIdentifier("historyEmptyState")
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 0)
            .onChange(of: days.map(\.id), initial: true) { scrollToFocus(proxy) }
        }
        .navigationTitle("Listening History")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Title, Podcast, Description"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle(isOn: $onlyUnfinished) {
                        Label("Not Finished Only", systemImage: "circle.lefthalf.filled")
                    }
                    .accessibilityIdentifier("historyUnfinished")
                } label: {
                    Label("Filter", systemImage: onlyUnfinished
                          ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
                .accessibilityIdentifier("historyFilterMenu")
            }
        }
        .navigationDestination(item: $statsMonth) { ListeningStatsView(focusedMonth: $0.start) }
        .sheet(item: $selectedEpisode) { EpisodeDetailView(episode: $0) }
        .sheet(item: $addingToPlaylist) { AddToPlaylistView(episode: $0) }
        .task {
            let service = ListeningHistoryService(context: context, calendar: calendar)
            service.reload()
            self.service = service
            update()
        }
        .onChange(of: latest.first?.endedAt) { reload() }
        // Marked played or added somewhere in a sheet: the filters may see it differently now.
        .onChange(of: selectedEpisode == nil && addingToPlaylist == nil) { _, isClosed in if isClosed { reload() } }
        .onChange(of: query) { update() }
    }

    @ViewBuilder
    private func row(_ entry: HistoryEntry) -> some View {
        let episode = service?.episode(entry.id)
        HistoryRow(entry: entry, episode: episode,
                   playlist: entry.lastPlaylist.flatMap { id in playlists.first { $0.playlistID == id } })
            .contentShape(.rect)
            .onTapGesture { if let episode { selectedEpisode = episode } }
            .modifier(HistoryActions(episode: episode, onAddToPlaylist: { addingToPlaylist = episode }))
    }

    private func heading(top: CGFloat = 12, @ViewBuilder _ content: () -> some View) -> some View {
        content()
            .padding(.top, top)
            .listRowSeparator(.hidden)
    }

    /// The month with "Statistik ›" above its first day (A76).
    private func monthHeading(_ day: Date) -> some View {
        HStack {
            Text(day, format: .dateTime.month(.wide).year())
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            // A button, not a link: a link would turn the whole row into one.
            Button {
                statsMonth = HistoryMonth(start: day)
            } label: {
                HStack(spacing: 2) {
                    Text("Statistics")
                    Image(systemName: "chevron.right").font(.caption.bold()).accessibilityHidden(true)
                }
                .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Statistics for \(day.formatted(.dateTime.month(.wide).year()))"))
            .accessibilityIdentifier("historyMonthStats")
        }
    }

    private func dayHeading(_ day: HistoryDay) -> some View {
        HStack {
            Text(dayTitle(day.id))
            Spacer()
            if day.listenedSeconds >= 60 {
                Text(day.listenedSeconds.durationText)
                    .accessibilityLabel(Text("Listened \(day.listenedSeconds.durationText)"))
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("historyDay")
    }

    /// "Heute", "Gestern", else "Mo., 6. Okt." (with the year if it is not this year).
    private func dayTitle(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        let thisYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        return day.formatted(thisYear ? .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                                      : .dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
    }

    @ViewBuilder private var emptyState: some View {
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            ContentUnavailableView.search(text: search)
        } else if service?.entries.isEmpty ?? true {
            ContentUnavailableView("Nothing Heard Yet", systemImage: "clock.arrow.circlepath",
                                   description: Text("Every episode you start shows up here."))
        } else {
            ContentUnavailableView("Nothing Here", systemImage: "line.3.horizontal.decrease.circle",
                                   description: onlyUnfinished
                                       ? Text("No started episode is waiting to be finished.")
                                       : Text("You have not listened to any episode of these podcasts."))
        }
    }

    private func reload() {
        service?.reload()
        update()
    }

    private func update() {
        guard let service else { return }
        days = service.days(query)
        let isPlain = search.trimmingCharacters(in: .whitespaces).isEmpty && !onlyUnfinished
        let yearAgo = isPlain ? service.yearAgo(filter: filter) : []
        var items: [HistoryItem] = []
        if !yearAgo.isEmpty {
            items.append(HistoryItem(id: "yearAgo", kind: .yearAgo))
            items += yearAgo.map { HistoryItem(id: "yearAgo-\($0.id.uuid)", kind: .entry($0)) }
        }
        for (index, day) in days.enumerated() {
            let key = day.id.timeIntervalSinceReferenceDate
            if index == 0 || !calendar.isDate(days[index - 1].id, equalTo: day.id, toGranularity: .month) {
                items.append(HistoryItem(id: HistoryItem.monthID(day.id), kind: .month(day.id)))
            }
            items.append(HistoryItem(id: HistoryItem.dayID(day.id), kind: .day(day)))
            items += day.entries.map { HistoryItem(id: "\(key)-\($0.id.uuid)", kind: .entry($0)) }
        }
        self.items = items
    }

    /// From the statistics: once, to the latest day of the period (A76), with its month
    /// heading above it (the latest day of a period always starts its month here).
    private func scrollToFocus(_ proxy: ScrollViewProxy) {
        guard !didFocus, let focus, !days.isEmpty else { return }
        didFocus = true
        guard let day = ListeningHistory.latestDay(in: focus, of: days) else { return }
        let month = HistoryItem.monthID(day)
        proxy.scrollTo(items.contains { $0.id == month } ? month : HistoryItem.dayID(day), anchor: .top)
    }
}

/// The month above its first day, for "Statistik ›" (A76).
private struct HistoryMonth: Hashable {
    var start: Date
}

/// One row of the list: a heading or an episode.
private struct HistoryItem: Identifiable {
    enum Kind {
        case yearAgo
        case month(Date)
        case day(HistoryDay)
        case entry(HistoryEntry)
    }

    var id: String
    var kind: Kind

    static func dayID(_ day: Date) -> String { "day-\(day.timeIntervalSinceReferenceDate)" }
    static func monthID(_ day: Date) -> String { "month-\(day.timeIntervalSinceReferenceDate)" }
}

/// One episode in the listening history (concept §4.12): artwork, podcast, title, what has
/// played as a bar, the episode's state, the chapter it goes on with and the playlist of its
/// last session. Gone episodes: grey, from the snapshot, without actions.
private struct HistoryRow: View {
    let entry: HistoryEntry
    let episode: Episode?
    let playlist: Playlist?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ArtworkView(url: episode?.imageURL ?? episode?.podcast?.artworkURL, cornerRadius: 6)
                .frame(width: 52)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.podcastTitle)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                Text(entry.title)
                    .font(.headline)
                    .lineLimit(2)
                if let fraction = entry.heardFraction, let duration = entry.duration {
                    HeardBar(heard: entry.heard, duration: duration)
                        .accessibilityElement()
                        .accessibilityLabel(Text("Heard"))
                        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
                }
                if let episode {
                    EpisodeStatusLine(episode: episode, showsProgress: entry.heardFraction == nil)
                    if let chapter = nextChapter(of: episode) {
                        Label {
                            Text("Continues at “\(chapter)”").lineLimit(1)
                        } icon: {
                            Image(systemName: "list.bullet")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No longer available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let playlist {
                    PlaylistTag(playlist: playlist)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let episode {
                PlayButton(episode: episode)
            }
        }
        .opacity(episode == nil ? 0.5 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("historyRow")
    }

    /// The chapter a started, unplayed episode goes on with (A72).
    private func nextChapter(of episode: Episode) -> String? {
        guard !episode.isPlayed, episode.playbackPosition > 0 else { return nil }
        let title = ChapterSelection.context(at: episode.playbackPosition, in: episode.chapters).chapter?.title
        return title?.isEmpty == false ? title : nil
    }
}

/// The parts of the episode that played, on a bar over the whole episode (A71).
private struct HeardBar: View {
    let heard: [ClosedRange<TimeInterval>]
    let duration: TimeInterval

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                ForEach(heard, id: \.self) { part in
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(3, geometry.size.width * (part.upperBound - part.lowerBound) / duration))
                        .offset(x: geometry.size.width * part.lowerBound / duration)
                }
            }
        }
        .frame(height: 4)
        .clipShape(.capsule)
    }
}

/// Swipes and context menu of a row (concept §4.12, like A24): "Als Nächstes" and "Am Ende"
/// to the right, "Zu Playlist …" and "Von vorn" to the left; the menu also plays on.
private struct HistoryActions: ViewModifier {
    let episode: Episode?
    let onAddToPlaylist: () -> Void
    @Environment(UpNextService.self) private var upNext

    func body(content: Content) -> some View {
        if let episode {
            content
                .swipeActions(edge: .leading) {
                    playNextButton(episode).tint(.orange)
                    playLastButton(episode).tint(.blue)
                }
                .swipeActions(edge: .trailing) {
                    addToPlaylistButton.tint(.indigo)
                    fromStartButton(episode).tint(.gray)
                }
                .contextMenu {
                    Button("Play", systemImage: "play") { upNext.play(episode) }
                    fromStartButton(episode)
                    playNextButton(episode)
                    playLastButton(episode)
                    addToPlaylistButton
                }
        } else {
            content
        }
    }

    /// From the start, after the podcast's intro (A28).
    private func fromStartButton(_ episode: Episode) -> some View {
        Button("Play from the Start", systemImage: "backward.end") {
            let start = PlaybackRules.startPosition(
                stored: 0, isPlayed: false, duration: episode.duration,
                skipIntro: TimeInterval(episode.podcast?.skipIntroSeconds ?? 0))
            upNext.play(episode, at: start)
        }
        .accessibilityIdentifier("historyFromStart")
    }

    private func playNextButton(_ episode: Episode) -> some View {
        Button("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") { upNext.playNext(episode) }
            .accessibilityIdentifier("historyPlayNext")
    }

    private func playLastButton(_ episode: Episode) -> some View {
        Button("Play Last", systemImage: "text.line.last.and.arrowtriangle.forward") { upNext.playLast(episode) }
    }

    private var addToPlaylistButton: some View {
        Button("Add to Playlist…", systemImage: "music.note.list", action: onAddToPlaylist)
            .accessibilityIdentifier("historyAddToPlaylist")
    }
}
