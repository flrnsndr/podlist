import Charts
import PodlistKit
import SwiftUI

/// One card of the statistics page (plan-hoerstatistik §7): a small heading, a big number or
/// name, a sentence and, where it helps, a chart. VoiceOver reads each card as one element.
struct StatCard<Chart: View>: View {
    let title: String
    var value: String?
    var sentence: String?
    var symbolName: String?
    @ViewBuilder var chart: Chart

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                // Title, value and sentence are one VoiceOver element; the chart stays its own
                // element with its marks and Audio Graph.
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(title)
                    } icon: {
                        if let symbolName { Image(systemName: symbolName) }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    if let value {
                        Text(value)
                            .font(.title2.bold())
                            .fontDesign(.rounded)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let sentence {
                        Text(sentence)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
                chart
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension StatCard where Chart == EmptyView {
    init(title: String, value: String? = nil, sentence: String? = nil, symbolName: String? = nil) {
        self.init(title: title, value: value, sentence: sentence, symbolName: symbolName) { EmptyView() }
    }
}

/// Renders one insight as its card.
struct InsightCard: View {
    let insight: Insight
    let report: StatsReport
    let lookup: StatsLookup
    let isCurrentPeriod: Bool
    @Environment(\.calendar) private var calendar

    private var isYear: Bool { report.period.kind == .year }

    var body: some View {
        switch insight {
        // A. Overview
        case let .totalTime(total):
            TotalTimeCard(total: total, report: report)
        case .conversion:
            // Part of the total time card (plan §7).
            EmptyView()
        case let .episodes(finished, started):
            StatCard(
                title: String(localized: "Episodes"),
                value: String(localized: "\(finished) episodes finished"),
                sentence: started > 0 ? String(localized: "\(started) more started.") : nil,
                symbolName: "checkmark.circle")
        case let .listeningDays(days):
            StatCard(
                title: String(localized: "Listening Days"),
                value: "\(days.days)",
                sentence: String(localized: "You listened on \(days.days) of \(days.daysInPeriod) days, \(days.averagePerDay.durationText) a day on average."),
                symbolName: "calendar")
        case let .podcastVariety(count, tone):
            StatCard(
                title: String(localized: "Podcasts"),
                value: String(localized: "\(count) podcasts"),
                sentence: tone.sentence,
                symbolName: "square.stack")

        // B. Favorites
        case let .topPodcasts(top):
            StatCard(title: String(localized: "Top Podcasts"), symbolName: "trophy") {
                TopPodcastsList(top: top, lookup: lookup)
            }
        case let .playlists(favorite, all):
            StatCard(
                title: String(localized: "Playlists"),
                sentence: String(localized: "\(lookup.name(of: favorite.playlist)) is your playlist: \(favorite.share.percentText) of your time."),
                symbolName: "music.note.list"
            ) {
                PlaylistDonut(shares: all, lookup: lookup)
            }
        case let .genre(name, share):
            StatCard(
                title: String(localized: "Genre"),
                value: name,
                sentence: [String(localized: "\(share.percentText) of your listening."), GenreQuip.quip(for: name)]
                    .compactMap(\.self).joined(separator: " "),
                symbolName: "tag")
        case let .marathon(marathon):
            StatCard(
                title: String(localized: "Marathon"),
                value: marathon.seconds.durationText,
                sentence: String(localized: "In one go, on \(marathon.start.shortDayText), with \(marathon.podcast.title). Respect."),
                symbolName: "figure.run")
        case let .faithful(faithful):
            StatCard(
                title: String(localized: "Faithful Companion"),
                value: faithful.podcast.title,
                sentence: faithfulSentence(faithful),
                symbolName: "heart")
        case let .binge(binge):
            StatCard(
                title: String(localized: "Binge"),
                value: String(localized: "\(binge.episodes) episodes"),
                sentence: String(localized: "Of \(binge.podcast.title) on a single day: \(binge.day.dayText)."),
                symbolName: "flame")
        case let .newDiscovery(discovery):
            StatCard(
                title: String(localized: "New Discovery"),
                value: discovery.podcast.title,
                sentence: String(localized: "Subscribed on \(discovery.subscribedAt.shortDayText) and already number \(discovery.rank)."),
                symbolName: "sparkles")

        // C. Records
        case let .recordDay(record):
            StatCard(
                title: String(localized: "Record Day"),
                value: record.day.dayText,
                sentence: String(localized: "\(record.seconds.durationText), mostly \(record.topPodcast.title)."),
                symbolName: "medal")
        case let .streak(streak):
            StatCard(
                title: String(localized: "Longest Streak"),
                value: TimeInterval.daysText(streak.longest),
                sentence: streak.current.map { String(localized: "Current streak: \(TimeInterval.daysText($0)). Keep it going!") }
                    ?? String(localized: "In a row, starting \(streak.longestStart.shortDayText)."),
                symbolName: "flame.fill")
        case let .longestBreak(days, start):
            StatCard(
                title: String(localized: "Longest Silence"),
                value: TimeInterval.daysText(days),
                sentence: String(localized: "Without a podcast from \(start.shortDayText). Vacation?"),
                symbolName: "speaker.slash")
        case let .strongestStretch(stretch):
            StatCard(
                title: isYear ? String(localized: "Strongest Month") : String(localized: "Strongest Week"),
                value: isYear
                    ? stretch.start.formatted(.dateTime.month(.wide))
                    : String(localized: "Week of \(stretch.start.shortDayText)"),
                sentence: String(localized: "\(stretch.seconds.durationText) of listening."),
                symbolName: "chart.bar")

        // D. Rhythm
        case let .heatmap(heatmap):
            StatCard(
                title: String(localized: "When You Listen"),
                sentence: String(localized: "You like listening best \(heatmap.peakPart.phrase(weekend: heatmap.peakIsWeekend))."),
                symbolName: "square.grid.3x3"
            ) {
                HeatmapChart(heatmap: heatmap)
            }
        case let .listenerType(profile):
            ListenerTypeCard(profile: profile)
        case let .favoriteWeekday(weekday, weekendShare):
            StatCard(
                title: String(localized: "Favorite Day"),
                value: calendar.standaloneWeekdaySymbols[weekday - 1],
                sentence: String(localized: "\(calendar.standaloneWeekdaySymbols[weekday - 1]) belongs to you and your podcasts. \(weekendShare.percentText) of your listening is on weekends."),
                symbolName: "calendar.day.timeline.left")

        // E. Style
        case let .speed(speed):
            StatCard(
                title: String(localized: "Speed"),
                value: speed.average.speedText,
                sentence: speedSentence(speed),
                symbolName: "hare")
        case let .skipped(seconds):
            StatCard(
                title: String(localized: "Skipped"),
                value: seconds.durationText,
                sentence: String(localized: "Ads? What ads?"),
                symbolName: "forward")
        case let .completion(completion):
            StatCard(
                title: String(localized: "Staying Power"),
                value: completion.rate.percentText,
                sentence: completionSentence(completion),
                symbolName: "checkmark.seal")
        case let .sleep(sleep):
            StatCard(
                title: String(localized: "Falling Asleep"),
                value: String(localized: "\(sleep.count) times"),
                sentence: String(localized: "Most often with \(sleep.podcast.title) (\(sleep.podcastCount) times). Compliments to the voice."),
                symbolName: "moon.zzz")
        case let .freshness(rows):
            StatCard(
                title: String(localized: "How Fresh?"),
                sentence: String(localized: "Time from release to listening, per playlist."),
                symbolName: "leaf"
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(rows, id: \.playlist) { row in
                        HStack {
                            StatsPlaylistIcon(playlist: row.playlist, lookup: lookup)
                            Text(lookup.name(of: row.playlist))
                            Spacer()
                            Text(row.median.roughText).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }

        // F. Finds
        case let .archaeologist(moment):
            StatCard(
                title: String(localized: "Archaeologist"),
                value: moment.date.monthText,
                sentence: String(localized: "Dug up: \(moment.title) by \(moment.podcast.title)."),
                symbolName: "fossil.shell")
        case let .quickest(moment, delay):
            StatCard(
                title: String(localized: "Lightning Listener"),
                value: delay.roughText,
                sentence: String(localized: "\(moment.podcast.title), right after release. Were you in the studio?"),
                symbolName: "bolt")
        case let .repeated(moment, times):
            StatCard(
                title: String(localized: "Repeat Offender"),
                value: String(localized: "\(times) times"),
                sentence: String(localized: "\(moment.title). Must be good."),
                symbolName: "repeat")
        case let .longestEpisode(moment, duration):
            StatCard(
                title: String(localized: "Heavyweight"),
                value: duration.durationText,
                sentence: String(localized: "\(moment.title). And you made it through."),
                symbolName: "scalemass")
        case let .shortestEpisode(moment, duration):
            StatCard(
                title: String(localized: "Podcast Snack"),
                value: duration.durationText,
                sentence: String(localized: "\(moment.title). A podcast for in between."),
                symbolName: "takeoutbag.and.cup.and.straw")
        case let .longHaul(moment, days):
            StatCard(
                title: String(localized: "Long Haul"),
                value: TimeInterval.daysText(days),
                sentence: String(localized: "From minute 1 to the end of \(moment.title). Good things take time."),
                symbolName: "tortoise")
        case let .nightShift(moment):
            StatCard(
                title: String(localized: "Night Shift"),
                value: moment.date.formatted(date: .omitted, time: .shortened),
                sentence: String(localized: "\(moment.podcast.title) was still playing. Everything okay?"),
                symbolName: "moon.haze")
        case let .firstAndLast(first, last):
            StatCard(
                title: String(localized: "First and Last"),
                sentence: isCurrentPeriod
                    ? String(localized: "Your year began with \(first.title). Most recently: \(last.title).")
                    : String(localized: "Your year began with \(first.title) and ended with \(last.title)."),
                symbolName: "book.closed")
        case let .holidays(listens):
            StatCard(title: String(localized: "Holiday Listener"), symbolName: "gift") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(listens, id: \.holiday) { listen in
                        Text(verbatim: "\(listen.holiday.name), \(listen.moment.date.formatted(date: .omitted, time: .shortened)): \(listen.moment.podcast.title)")
                            .font(.subheadline)
                    }
                }
            }

        // G. Conscience
        case let .neglected(podcasts):
            StatCard(
                title: String(localized: "Neglected"),
                sentence: String(localized: "Not a minute heard. They miss you."),
                symbolName: "heart.slash"
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(podcasts, id: \.podcast) { item in
                        HStack {
                            Text(item.podcast.title)
                            Spacer()
                            Text("\(item.newEpisodes) new episodes").foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
        case let .backlog(backlog):
            StatCard(
                title: String(localized: "The Pile"),
                value: backlog.seconds.durationText,
                sentence: String(localized: "At your pace, you need \(TimeInterval.daysText(backlog.days)) to catch up. Without sleep: \(TimeInterval.daysText(backlog.nonstopDays))."),
                symbolName: "books.vertical")
        case let .unheardSubscriptions(count):
            StatCard(
                title: String(localized: "Subscribed, Not Heard"),
                value: "\(count)",
                sentence: String(localized: "\(count) subscriptions not heard once this year. Time to tidy up?"),
                symbolName: "archivebox")

        // H. Trends
        case let .trend(trend):
            StatCard(
                title: String(localized: "Listening Over Time"),
                sentence: isYear
                    ? String(localized: "On average \(trend.average.durationText) a month.")
                    : String(localized: "On average \(trend.average.durationText) a day."),
                symbolName: "chart.bar.xaxis"
            ) {
                TrendChart(trend: trend, isYear: isYear)
            }
        case let .riser(change):
            StatCard(
                title: String(localized: "On the Rise"),
                value: change.podcast.title,
                sentence: String(localized: "From \(change.fromShare.percentText) to \(change.toShare.percentText) of your listening."),
                symbolName: "arrow.up.right"
            ) {
                ShareLineChart(values: change.monthly, title: change.podcast.title)
            }
        case let .cooled(change):
            StatCard(
                title: String(localized: "Cooled Off"),
                value: change.podcast.title,
                sentence: change.toRank.map { String(localized: "You two had something. Once number \(change.fromRank), now number \($0).") }
                    ?? String(localized: "You two had something. Once number \(change.fromRank), now not at all."),
                symbolName: "snowflake")
        case let .playlistShift(shift):
            StatCard(
                title: String(localized: "Playlist Shift"),
                sentence: shift.highlight.map(growthSentence),
                symbolName: "chart.line.uptrend.xyaxis"
            ) {
                PlaylistShiftChart(shift: shift, lookup: lookup)
            }
        case let .speedTrend(trend):
            StatCard(
                title: String(localized: "Speed Over Time"),
                sentence: speedTrendSentence(trend),
                symbolName: "speedometer"
            ) {
                SpeedLineChart(values: trend.monthly)
            }
        case let .daytimeShift(from, to):
            StatCard(
                title: String(localized: "Time of Day"),
                sentence: String(localized: "You used to listen \(from.adverb), now \(to.adverb)."),
                symbolName: "sun.and.horizon")
        case let .yearChapters(months):
            StatCard(title: String(localized: "Your Year in Chapters"), symbolName: "books.vertical.fill") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(months, id: \.month) { month in
                        HStack(spacing: 10) {
                            Text(month.month.formatted(.dateTime.month(.abbreviated)))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 44, alignment: .leading)
                            ArtworkView(url: lookup.artworkURL(of: month.podcast), cornerRadius: 4).frame(width: 28)
                            Text(month.podcast.title).font(.subheadline).lineLimit(1)
                        }
                    }
                }
            }
        case let .newVsLoyal(newInTop, loyal):
            StatCard(
                title: String(localized: "New and Loyal"),
                value: newInTop == 0
                    ? String(localized: "None of your top 5 is new this year.")
                    : String(localized: "\(newInTop) of your top 5 are new this year."),
                sentence: loyal.isEmpty ? nil
                    : String(localized: "Loyal for years: \(loyal.map(\.title).formatted(.list(type: .and)))."),
                symbolName: "person.2")
        }
    }

    private func faithfulSentence(_ faithful: Faithful) -> String {
        switch (isYear, faithful.count == faithful.outOf) {
        case (false, true): String(localized: "With you every single week.")
        case (false, false): String(localized: "With you in \(faithful.count) of \(faithful.outOf) weeks.")
        case (true, true): String(localized: "With you every single month.")
        case (true, false): String(localized: "With you in \(faithful.count) of \(faithful.outOf) months.")
        }
    }

    private func speedSentence(_ speed: Speed) -> String {
        guard speed.average > 1 else { return String(localized: "Taking your time. Nice.") }
        let saved = String(localized: "You saved \(speed.savedSeconds.durationText).")
        return [saved, speed.conversion?.sentence].compactMap(\.self).joined(separator: " ")
    }

    private func completionSentence(_ completion: Completion) -> String {
        let rate = String(localized: "That's how many of your episodes you finish.")
        guard let lingering = completion.lingering else { return rate }
        let minute = Int(lingering.position / 60)
        let stuck = String(localized: "Stuck at minute \(minute) since \(lingering.since.monthText): \(lingering.title).")
        return "\(rate) \(stuck)"
    }

    private func growthSentence(_ growth: PlaylistGrowth) -> String {
        let name = lookup.name(of: growth.playlist)
        let since = growth.since.formatted(.dateTime.month(.wide))
        if growth.factor < 2.5 { return String(localized: "\(name) has doubled since \(since).") }
        return String(localized: "\(name) has grown \(Int(growth.factor.rounded()))-fold since \(since).")
    }

    private func speedTrendSentence(_ trend: SpeedTrend) -> String {
        let from = trend.from.value.speedText
        let to = trend.to.value.speedText
        let fromMonth = trend.from.month.formatted(.dateTime.month(.wide))
        let toMonth = trend.to.month.formatted(.dateTime.month(.wide))
        return trend.to.value > trend.from.value
            ? String(localized: "You're getting faster: from \(from) in \(fromMonth) to \(to) in \(toMonth).")
            : String(localized: "You're slowing down: from \(from) in \(fromMonth) to \(to) in \(toMonth).")
    }
}

private extension VarietyTone {
    var sentence: String {
        switch self {
        case .focused: String(localized: "You know what you want.")
        case .balanced: String(localized: "A good mix.")
        case .explorer: String(localized: "You're open to new things.")
        }
    }
}

// MARK: Highlight cards

/// I1 as the big card at the top, with the comparison and "recorded since".
private struct TotalTimeCard: View {
    let total: TotalTime
    let report: StatsReport

    private var showsContentTime: Bool {
        total.listenedSeconds > 0 && abs(total.contentSeconds / total.listenedSeconds - 1) >= 0.05
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Listening Time")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(total.listenedSeconds.durationText)
                .font(.largeTitle.bold())
                .fontDesign(.rounded)
            if showsContentTime {
                Text("That was \(total.contentSeconds.durationText) of episodes.")
            }
            if let conversion = report.conversion {
                Text(conversion.sentence)
            }
            if let change = total.change {
                Text(changeText(change))
                    .foregroundStyle(change >= 0 ? .green : .orange)
            }
            if let start = report.recordingStartedAt {
                Text("Recorded since \(start.formatted(date: .long, time: .omitted)).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.tint.opacity(0.12), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("statsTotal")
    }

    private func changeText(_ change: Double) -> String {
        let amount = abs(change).percentText
        return switch (report.period.kind, change >= 0) {
        case (.month, true): String(localized: "\(amount) more than last month.")
        case (.month, false): String(localized: "\(amount) less than last month.")
        case (.year, true): String(localized: "\(amount) more than last year.")
        case (.year, false): String(localized: "\(amount) less than last year.")
        }
    }
}

/// I18 as the second big card.
private struct ListenerTypeCard: View {
    let profile: ListenerProfile

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: profile.symbolName)
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.indigo.gradient, in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Listener Type")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(profile.title)
                    .font(.title3.bold())
                    .fontDesign(.rounded)
                Text(profile.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.indigo.opacity(0.12), in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Lists and charts

private struct TopPodcastsList: View {
    let top: [PodcastShare]
    let lookup: StatsLookup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(top.enumerated()), id: \.offset) { index, item in
                HStack(spacing: 10) {
                    Text(verbatim: "\(index + 1)").font(.headline.monospacedDigit()).frame(width: 20)
                    ArtworkView(url: lookup.artworkURL(of: item.podcast), cornerRadius: 6).frame(width: 40)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.podcast.title).font(.subheadline.weight(.medium)).lineLimit(1)
                        GeometryReader { proxy in
                            Capsule()
                                .fill(.tint)
                                .frame(width: max(4, proxy.size.width * item.share / (top.first?.share ?? 1)))
                        }
                        .frame(height: 6)
                        Text("\(item.seconds.durationText) · \(item.share.percentText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Number \(index + 1): \(item.podcast.title), \(item.seconds.durationText), \(item.share.percentText)"))
            }
        }
    }
}

private struct PlaylistDonut: View {
    let shares: [PlaylistShare]
    let lookup: StatsLookup

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            Chart(shares, id: \.playlist) { share in
                SectorMark(angle: .value("Share", share.seconds), innerRadius: .ratio(0.6), angularInset: 1.5)
                    .foregroundStyle(lookup.color(of: share.playlist))
                    .accessibilityLabel(lookup.name(of: share.playlist))
                    .accessibilityValue(share.share.percentText)
            }
            .frame(width: 110, height: 110)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shares.prefix(6), id: \.playlist) { share in
                    HStack(spacing: 6) {
                        StatsPlaylistIcon(playlist: share.playlist, lookup: lookup, size: 20)
                        Text(lookup.name(of: share.playlist)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(share.share.percentText).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
    }
}

private struct HeatmapChart: View {
    let heatmap: Heatmap
    @Environment(\.calendar) private var calendar

    /// Three-hour blocks, weekdays in the order of the device calendar.
    private struct Cell: Identifiable {
        var row: Int
        var weekday: String
        var block: Int
        var seconds: TimeInterval
        var id: String { "\(row)-\(block)" }
    }

    private var cells: [Cell] {
        (0..<7).flatMap { row in
            let weekday = (calendar.firstWeekday - 1 + row) % 7
            let name = calendar.shortStandaloneWeekdaySymbols[weekday]
            return (0..<8).map { block in
                Cell(row: row, weekday: name, block: block * 3,
                     seconds: heatmap.seconds[weekday][(block * 3)..<(block * 3 + 3)].reduce(0, +))
            }
        }
    }

    var body: some View {
        let cells = cells
        let maximum = max(cells.map(\.seconds).max() ?? 1, 1)
        let names = cells.map(\.weekday).uniqued()
        // Numeric edges so every cell fills its block; the first weekday is the top row.
        Chart(cells) { cell in
            RectangleMark(
                xStart: .value("Hour", cell.block), xEnd: .value("Hour", cell.block + 3),
                yStart: .value("Weekday", 6 - cell.row), yEnd: .value("Weekday", 7 - cell.row))
            .foregroundStyle(Color.accentColor.opacity(0.06 + 0.94 * cell.seconds / maximum))
            .cornerRadius(3)
            .accessibilityLabel("\(cell.weekday), \(cell.block):00")
            .accessibilityValue(cell.seconds.durationText)
        }
        .chartXScale(domain: 0...24)
        .chartYScale(domain: 0...7)
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                AxisValueLabel { Text(verbatim: "\(value.as(Int.self) ?? 0)") }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: (0..<7).map { Double($0) + 0.5 }) { value in
                AxisValueLabel {
                    let row = 6 - Int(value.as(Double.self) ?? 0)
                    Text(verbatim: names.indices.contains(row) ? names[row] : "")
                }
            }
        }
        .frame(height: 200)
    }
}

private struct TrendChart: View {
    let trend: Trend
    let isYear: Bool

    var body: some View {
        Chart {
            ForEach(trend.bars, id: \.start) { bar in
                BarMark(
                    x: .value("Date", bar.start, unit: isYear ? .month : .day),
                    y: .value("Hours", bar.seconds / 3_600))
                .accessibilityLabel(isYear ? bar.start.formatted(.dateTime.month(.wide)) : bar.start.shortDayText)
                .accessibilityValue(bar.seconds.durationText)
            }
            RuleMark(y: .value("Average", trend.average / 3_600))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary)
        }
        .chartYAxisLabel(String(localized: "Hours"))
        .frame(height: 160)
    }
}

private struct ShareLineChart: View {
    let values: [MonthValue]
    let title: String

    var body: some View {
        Chart(values, id: \.month) { value in
            LineMark(x: .value("Month", value.month, unit: .month), y: .value("Share", value.value))
                .interpolationMethod(.catmullRom)
            PointMark(x: .value("Month", value.month, unit: .month), y: .value("Share", value.value))
                .accessibilityLabel(value.month.formatted(.dateTime.month(.wide)))
                .accessibilityValue(value.value.percentText)
        }
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { Text((value.as(Double.self) ?? 0).percentText) }
            }
        }
        .frame(height: 120)
    }
}

private struct SpeedLineChart: View {
    let values: [MonthValue]

    var body: some View {
        Chart(values, id: \.month) { value in
            LineMark(x: .value("Month", value.month, unit: .month), y: .value("Speed", value.value))
                .interpolationMethod(.catmullRom)
            PointMark(x: .value("Month", value.month, unit: .month), y: .value("Speed", value.value))
                .accessibilityLabel(value.month.formatted(.dateTime.month(.wide)))
                .accessibilityValue(value.value.speedText)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 120)
    }
}

private struct PlaylistShiftChart: View {
    let shift: PlaylistShift
    let lookup: StatsLookup

    private struct Point: Identifiable {
        var month: Date
        var name: String
        var share: Double
        var id: String { "\(month.timeIntervalSinceReferenceDate)-\(name)" }
    }

    var body: some View {
        let points = shift.months.flatMap { month in
            month.shares.map { Point(month: month.month, name: lookup.name(of: $0.playlist), share: $0.share) }
        }
        let names = points.map(\.name).uniqued()
        Chart(points) { point in
            AreaMark(x: .value("Month", point.month, unit: .month), y: .value("Share", point.share), stacking: .normalized)
                .foregroundStyle(by: .value("Playlist", point.name))
                .accessibilityLabel("\(point.name), \(point.month.formatted(.dateTime.month(.wide)))")
                .accessibilityValue(point.share.percentText)
        }
        .chartForegroundStyleScale(domain: names, range: names.map { name in
            let id = shift.months.flatMap(\.shares).first { lookup.name(of: $0.playlist) == name }?.playlist
            return lookup.color(of: id ?? nil)
        })
        .chartYAxis(.hidden)
        .frame(height: 160)
    }
}

extension Sequence where Element: Hashable {
    /// The elements in order, without repeats.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
