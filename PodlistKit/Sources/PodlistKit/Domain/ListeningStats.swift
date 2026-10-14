import Foundation

/// Evaluates the listening log for a month or a year (concept §4.11, plan-hoerstatistik
/// §5–§6): pure, on values, with the calendar and `now` injected.
public enum ListeningStats {
    /// The report for `period`. `sessions` is the whole log (comparisons and "first heard"
    /// need earlier periods too).
    public static func report(
        for period: StatsPeriod, sessions: [ListeningRecord], library: StatsLibrary, calendar: Calendar, now: Date
    ) -> StatsReport {
        let context = Context(period: period, records: sessions, library: library, calendar: calendar, now: now)
        guard context.total > 0 else { return StatsReport(period: period) }

        let recordingStartedAt = context.recordingStart.flatMap { context.interval.holds($0) ? $0 : nil }

        // Catalog order (the enum order of `Insight`): A, B, C, D, E, I25 + I37–I44, G, H.
        let insights: [Insight?] = [
            context.totalTime(), context.conversionOfTotal(), context.episodeCounts(), context.listeningDaysInsight(),
            context.podcastVariety(),
            context.topPodcasts(), context.playlistShares(), context.genre(), context.marathon(), context.faithful(),
            context.binge(), context.newDiscovery(),
            context.recordDay(), context.streak(), context.longestBreak(), context.strongestStretch(),
            context.heatmap(), context.listenerType(), context.favoriteWeekday(),
            context.speed(), context.skipped(), context.completion(), context.sleep(), context.freshness(),
            context.archaeologist(), context.quickest(), context.repeated(), context.longestEpisode(),
            context.shortestEpisode(), context.longHaul(), context.nightShift(), context.firstAndLast(),
            context.holidays(),
            context.neglected(), context.backlog(), context.unheardSubscriptions(),
            context.trend(), context.riser(), context.cooled(), context.playlistShift(), context.speedTrend(),
            context.daytimeShift(), context.yearChapters(), context.newVsLoyal(),
        ]
        return StatsReport(
            period: period, listenedSeconds: context.total, recordingStartedAt: recordingStartedAt,
            insights: insights.compactMap { $0 })
    }

    /// The periods of `kind` to page through: those with sessions, plus the one containing
    /// `now` (the default), oldest first.
    public static func periods(_ kind: StatsPeriod.Kind, sessions: [ListeningRecord], calendar: Calendar, now: Date) -> [StatsPeriod] {
        var periods = Set(sessions.map { StatsPeriod(kind, containing: $0.startedAt, calendar: calendar) })
        periods.insert(StatsPeriod(kind, containing: now, calendar: calendar))
        return periods.sorted()
    }
}
