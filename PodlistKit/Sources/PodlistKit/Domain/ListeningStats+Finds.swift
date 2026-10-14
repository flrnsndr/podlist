import Foundation

// F. Finds (I25, I37–I44).

extension ListeningStats.Context {
    func archaeologist() -> Insight? {
        let candidates = endedRecords.filter { index in
            let record = records[index]
            guard record.episodePublishedAt > .distantPast,
                  let limit = calendar.date(byAdding: .year, value: -1, to: record.startedAt)
            else { return false }
            return record.episodePublishedAt <= limit
        }
        guard let best = candidates.min(by: {
            let (a, b) = (records[$0], records[$1])
            return a.episodePublishedAt != b.episodePublishedAt ? a.episodePublishedAt < b.episodePublishedAt : a.startedAt < b.startedAt
        }) else { return nil }
        return .archaeologist(moment(record: best, date: records[best].episodePublishedAt))
    }

    func quickest() -> Insight? {
        guard let best = firstHeard.min(by: {
            $0.delay != $1.delay ? $0.delay < $1.delay : records[$0.record].startedAt < records[$1.record].startedAt
        }), atMost(best.delay, 3_600) else { return nil }
        return .quickest(moment(record: best.record, date: records[best.record].startedAt), delay: best.delay)
    }

    /// The latest finishing session per episode finished in the period.
    private var finishes: [EpisodeID: [Int]] {
        Dictionary(grouping: endedRecords.filter { records[$0].endReason == .finished }, by: { records[$0].episode })
            .mapValues { $0.sorted { records[$0].endedAt < records[$1].endedAt } }
    }

    func repeated() -> Insight? {
        let best = finishes.values.min {
            if $0.count != $1.count { return $0.count > $1.count }
            let (a, b) = (records[$0.last!], records[$1.last!])
            if a.endedAt != b.endedAt { return a.endedAt < b.endedAt }
            return a.episodeTitle < b.episodeTitle
        }
        guard let best, best.count >= 2 else { return nil }
        // ASSUMPTION: the moment is the last time it was finished in the period.
        return .repeated(moment(record: best.last!, date: records[best.last!].endedAt), times: best.count)
    }

    private func extremeFinish(longest: Bool) -> (record: Int, duration: TimeInterval)? {
        let entries = finishes.values.compactMap { sessions -> (record: Int, duration: TimeInterval)? in
            let index = sessions.last!
            guard let duration = records[index].episodeDuration, duration > 0 else { return nil }
            return (index, duration)
        }
        return entries.min {
            if $0.duration != $1.duration { return longest ? $0.duration > $1.duration : $0.duration < $1.duration }
            return records[$0.record].endedAt < records[$1.record].endedAt
        }
    }

    func longestEpisode() -> Insight? {
        guard let best = extremeFinish(longest: true), atLeast(best.duration, 2 * 3_600) else { return nil }
        return .longestEpisode(moment(record: best.record, date: records[best.record].endedAt), duration: best.duration)
    }

    func shortestEpisode() -> Insight? {
        guard let best = extremeFinish(longest: false), atMost(best.duration, 600) else { return nil }
        return .shortestEpisode(moment(record: best.record, date: records[best.record].endedAt), duration: best.duration)
    }

    func longHaul() -> Insight? {
        let entries = finishes.values.compactMap { sessions -> (record: Int, days: Int)? in
            let finish = sessions.last!
            // From the first listening after the episode was last finished (a re-listen starts over).
            let episode = records[finish].episode
            let earlier = records.indices.filter { records[$0].episode == episode && records[$0].startedAt < records[finish].startedAt }
            let lastFinish = earlier.filter { records[$0].endReason == .finished }.map { records[$0].endedAt }.max()
            let since = earlier.filter { index in lastFinish.map { records[index].startedAt >= $0 } ?? true }
            let first = since.min { records[$0].startedAt < records[$1].startedAt } ?? finish
            let days = daysBetween(calendar.startOfDay(for: records[first].startedAt), calendar.startOfDay(for: records[finish].endedAt))
            return (finish, days)
        }
        guard let best = entries.min(by: {
            $0.days != $1.days ? $0.days > $1.days : records[$0.record].endedAt < records[$1.record].endedAt
        }), best.days >= 30 else { return nil }
        return .longHaul(moment(record: best.record, date: records[best.record].endedAt), days: best.days)
    }

    func nightShift() -> Insight? {
        let night = pieces.filter { $0.hour < 4 }
        let seconds: (ListeningStats.Piece) -> TimeInterval = { $0.end.timeIntervalSince(self.calendar.startOfDay(for: $0.start)) }
        guard let best = night.min(by: {
            seconds($0) != seconds($1) ? seconds($0) > seconds($1) : $0.start < $1.start
        }) else { return nil }
        return .nightShift(moment(record: best.record, date: best.end))
    }

    func firstAndLast() -> Insight? {
        guard period.kind == .year, Set(pieces.map { monthStart($0.day) }).count >= 2 else { return nil }
        let first = pieces.min { $0.start < $1.start }!
        let last = pieces.max { $0.end < $1.end }!
        return .firstAndLast(
            first: moment(record: first.record, date: first.start), last: moment(record: last.record, date: last.end))
    }

    func holidays() -> Insight? {
        guard period.kind == .year, case let .year(year) = period else { return nil }
        let days: [(Holiday, DateComponents)] = [
            (.christmasEve, DateComponents(year: year, month: 12, day: 24)),
            (.newYearsEve, DateComponents(year: year, month: 12, day: 31)),
            (.newYearsDay, DateComponents(year: year, month: 1, day: 1)),
        ]
        var result: [HolidayListen] = []
        for (holiday, components) in days {
            guard let day = calendar.date(from: components) else { continue }
            let dayEnd = nextDay(day)
            guard let latest = pieces.filter({ $0.day == day }).max(by: { $0.end < $1.end }) else { continue }
            result.append(HolidayListen(
                holiday: holiday, moment: moment(record: latest.record, date: min(latest.end, dayEnd.addingTimeInterval(-1)))))
        }
        return result.isEmpty ? nil : .holidays(result)
    }
}
