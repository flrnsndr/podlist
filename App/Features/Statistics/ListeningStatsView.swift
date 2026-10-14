import PodlistKit
import SwiftData
import SwiftUI

/// Settings → Listening Stats (concept §4.11, plan-hoerstatistik §7): month or year, ‹ ›
/// through the periods with data, one card per insight in catalog order, share as an image.
struct ListeningStatsView: View {
    /// From the listening history: opens on the month containing this date (A76).
    var focusedMonth: Date?

    @Environment(\.modelContext) private var context
    @Environment(\.calendar) private var calendar
    @Query private var playlists: [Playlist]
    @Query private var podcasts: [Podcast]
    @State private var service: ListeningStatsService?
    @State private var kind = StatsPeriod.Kind.month
    @State private var periods: [StatsPeriod] = []
    @State private var period: StatsPeriod?
    @State private var report: StatsReport?
    @State private var isSharing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Period", selection: $kind) {
                    Text("Month").tag(StatsPeriod.Kind.month)
                    Text("Year").tag(StatsPeriod.Kind.year)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("statsKind")
                periodHeader
                if let report {
                    if report.isEmpty {
                        emptyView
                    } else {
                        content(report)
                        historyLink(report)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                }
            }
            .padding()
        }
        .navigationTitle("Listening Stats")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let report, !report.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Share", systemImage: "square.and.arrow.up") { isSharing = true }
                        .accessibilityIdentifier("statsShare")
                }
            }
        }
        .sheet(isPresented: $isSharing) {
            if let report {
                StatsShareSheet(report: report, lookup: lookup)
            }
        }
        .task {
            let service = ListeningStatsService(context: context, calendar: calendar)
            service.reload()
            self.service = service
            loadPeriods()
        }
        .onChange(of: kind) { loadPeriods() }
        .task(id: period) { await loadReport() }
    }

    private var lookup: StatsLookup { StatsLookup(playlists: playlists, podcasts: podcasts) }

    private var periodHeader: some View {
        let index = period.flatMap { periods.firstIndex(of: $0) }
        return HStack {
            Button("Previous Period", systemImage: "chevron.left") {
                if let index, index > 0 { period = periods[index - 1] }
            }
            .disabled(index.map { $0 == 0 } ?? true)
            .accessibilityIdentifier("statsPrevious")
            Spacer()
            Text(period?.title(in: calendar) ?? "")
                .font(.title3.bold())
                .accessibilityIdentifier("statsPeriod")
            Spacer()
            Button("Next Period", systemImage: "chevron.right") {
                if let index, index < periods.count - 1 { period = periods[index + 1] }
            }
            .disabled(index.map { $0 >= periods.count - 1 } ?? true)
            .accessibilityIdentifier("statsNext")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Listening Yet", systemImage: "chart.bar.xaxis")
        } description: {
            Text("Your listening stats are taking shape here. Listen to a few episodes and off you go.")
        }
        .padding(.top, 40)
    }

    @ViewBuilder
    private func content(_ report: StatsReport) -> some View {
        let isCurrent = report.period == periods.last
        let lookup = lookup
        // Total time and listener type as bigger cards at the top (plan §7).
        let highlights = report.insights.filter(\.isHighlight)
        ForEach(highlights, id: \.self) { insight in
            InsightCard(insight: insight, report: report, lookup: lookup, isCurrentPeriod: isCurrent)
        }
        ForEach(InsightSection.allCases, id: \.self) { section in
            let insights = report.insights.filter { $0.section == section && !$0.isHighlight }
            if !insights.isEmpty {
                Text(section.title)
                    .font(.title3.bold())
                    .padding(.top, 8)
                    .accessibilityAddTraits(.isHeader)
                ForEach(insights, id: \.self) { insight in
                    InsightCard(insight: insight, report: report, lookup: lookup, isCurrentPeriod: isCurrent)
                }
            }
        }
    }

    /// "Im Hörverlauf ›" (A76): the listening history at the latest day of this period.
    private func historyLink(_ report: StatsReport) -> some View {
        NavigationLink {
            ListeningHistoryView(focus: report.period.interval(in: calendar))
        } label: {
            // Framed like the insight cards above it.
            GroupBox {
                HStack {
                    Label("In Listening History", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("statsHistory")
    }

    private func loadPeriods() {
        guard let service else { return }
        periods = service.periods(kind)
        // Keep the time when switching: the month's year, or the year's latest month with data.
        // The first time, the month the listening history asked for (A76).
        let focus = period == nil ? focusedMonth.map { StatsPeriod(.month, containing: $0, calendar: calendar) } : nil
        let target = focus ?? period.map { current -> StatsPeriod in
            let lastMoment = current.interval(in: calendar).end.addingTimeInterval(-1)
            return StatsPeriod(kind, containing: lastMoment, calendar: calendar)
        }
        period = target.flatMap { target in periods.last { $0 <= target } } ?? periods.last
    }

    private func loadReport() async {
        guard let service, let period else { return }
        let report = await service.report(for: period)
        // The listener may have paged on meanwhile.
        if period == self.period { self.report = report }
    }
}

private extension Insight {
    var isHighlight: Bool {
        switch self {
        // I2 is shown inside the total time card.
        case .totalTime, .conversion, .listenerType: true
        default: false
        }
    }
}

extension InsightSection {
    var title: String {
        switch self {
        case .overview: String(localized: "Overview")
        case .favorites: String(localized: "Favorites")
        case .records: String(localized: "Records")
        case .rhythm: String(localized: "Rhythm")
        case .style: String(localized: "Listening Style")
        case .finds: String(localized: "Finds")
        case .conscience: String(localized: "Guilty Conscience")
        case .trends: String(localized: "Over Time")
        }
    }
}
