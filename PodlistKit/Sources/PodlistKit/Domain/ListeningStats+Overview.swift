import Foundation

// A. Overview (I1–I5) and B. Favorites (I6–I12).

extension ListeningStats.Context {
    // MARK: A

    func totalTime() -> Insight? {
        .totalTime(TotalTime(listenedSeconds: total, contentSeconds: content, change: change()))
    }

    /// Against the same span of the previous period (1–10 October ↔ 1–10 September, 2026 up
    /// to today ↔ 2025 up to the same day), and only when that span was recorded from its
    /// start: a half-recorded or still running period is never compared with a whole one.
    private func change() -> Double? {
        let previous = period.previous.interval(in: calendar)
        guard let recordingStart, calendar.startOfDay(for: recordingStart) <= previous.start else { return nil }
        var end = previous.end
        if containsNow {
            let elapsed = calendar.dateComponents([.month, .day, .hour, .minute, .second], from: interval.start, to: now)
            end = min(previous.end, calendar.date(byAdding: elapsed, to: previous.start) ?? previous.end)
        }
        let before = seconds(in: DateInterval(start: previous.start, end: end))
        return before > 0 ? (total - before) / before : nil
    }

    func conversionOfTotal() -> Insight? {
        guard atLeast(total, 3_600), let conversion = conversion(of: total, units: ConversionUnit.forTotal) else { return nil }
        return .conversion(conversion)
    }

    /// Distinct episodes finished in the period, and those listened without a finish.
    var finishedAndStarted: (finished: Set<EpisodeID>, started: Set<EpisodeID>) {
        let finished = Set(endedRecords.filter { records[$0].endReason == .finished }.map { records[$0].episode })
        let listened = Set(pieces.map { records[$0.record].episode })
        return (finished, listened.subtracting(finished))
    }

    func episodeCounts() -> Insight? {
        let (finished, started) = finishedAndStarted
        guard finished.count + started.count >= 1 else { return nil }
        return .episodes(finished: finished.count, started: started.count)
    }

    func listeningDaysInsight() -> Insight? {
        let days = listeningDays.count
        guard days >= 3 else { return nil }
        return .listeningDays(ListeningDays(days: days, daysInPeriod: periodDays.count, averagePerDay: total / Double(days)))
    }

    func podcastVariety() -> Insight? {
        let count = Set(pieces.map { key($0.record) }).count
        guard count >= 2 else { return nil }
        return .podcastVariety(count: count, tone: count <= 3 ? .focused : count <= 9 ? .balanced : .explorer)
    }

    // MARK: B

    func topPodcasts() -> Insight? {
        let ranking = podcastRanking(pieces)
        guard ranking.count >= 2 else { return nil }
        return .topPodcasts(ranking.prefix(5).map {
            PodcastShare(podcast: ref($0.key), seconds: $0.seconds, share: $0.seconds / total)
        })
    }

    func playlistShares() -> Insight? {
        let sorted = sortedPlaylists(playlistSeconds(pieces))
        guard sorted.count >= 2 else { return nil }
        let sum = sorted.reduce(0) { $0 + $1.seconds }
        let all = sorted.map { PlaylistShare(playlist: $0.playlist, seconds: $0.seconds, share: $0.seconds / sum) }
        // "Ohne Playlist" is a slice of the donut but never the favorite playlist.
        guard let favorite = all.first(where: { $0.playlist != nil }) else { return nil }
        return .playlists(favorite: favorite, all: all)
    }

    func genre() -> Insight? {
        guard atLeast(total, 3 * 3_600) else { return nil }
        var seconds: [String: TimeInterval] = [:]
        for piece in pieces {
            guard let id = records[piece.record].podcast, let genre = libraryPodcasts[id]?.categories.first else { continue }
            seconds[genre, default: 0] += piece.listened
        }
        let sum = seconds.values.reduce(0, +)
        guard sum > 0, let best = seconds.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).first
        else { return nil }
        return .genre(name: best.key, share: best.value / sum)
    }

    /// Sessions of one episode with less than 5 minutes between them count as one (plan §5).
    /// Not yet checked against the 45 minute condition.
    func longestRun() -> Marathon? {
        var best: Marathon?
        for (_, indexes) in Dictionary(grouping: endedRecords, by: { records[$0].episode }) {
            let sorted = indexes.sorted { records[$0].startedAt < records[$1].startedAt }
            var seconds = 0.0
            var start = records[sorted[0]].startedAt
            var first = sorted[0]
            var end = Date.distantPast
            func close() {
                let candidate = Marathon(seconds: seconds, start: start, podcast: ref(ofRecord: first))
                if best == nil || candidate.seconds > best!.seconds + 1e-9
                    || (abs(candidate.seconds - best!.seconds) <= 1e-9 && candidate.start < best!.start)
                {
                    best = candidate
                }
            }
            for index in sorted {
                let record = records[index]
                if end != .distantPast, record.startedAt.timeIntervalSince(end) >= 300 {
                    close()
                    seconds = 0
                    start = record.startedAt
                    first = index
                    end = .distantPast
                }
                seconds += record.listenedSeconds
                end = max(end, record.endedAt)
            }
            close()
        }
        return best
    }

    func marathon() -> Insight? {
        guard let run = longestRun(), atLeast(run.seconds, 45 * 60) else { return nil }
        return .marathon(run)
    }

    func faithful() -> Insight? {
        let unit: (Date) -> Date
        let outOf: Int
        switch period.kind {
        case .month:
            unit = weekStart
            outOf = Set(periodDays.map(weekStart)).count
        case .year:
            unit = monthStart
            outOf = Set(periodDays.map(monthStart)).count
        }
        var seen: [ListeningStats.PodcastKey: Set<Date>] = [:]
        for piece in pieces { seen[key(piece.record), default: []].insert(unit(piece.day)) }
        let seconds = Dictionary(uniqueKeysWithValues: podcastRanking(pieces).map { ($0.key, $0.seconds) })
        let best = seen.min {
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            if seconds[$0.key]! != seconds[$1.key]! { return seconds[$0.key]! > seconds[$1.key]! }
            return title($0.key) < title($1.key)
        }
        guard let best, best.value.count >= 3 else { return nil }
        return .faithful(Faithful(podcast: ref(best.key), count: best.value.count, outOf: outOf))
    }

    func binge() -> Insight? {
        struct Slot: Hashable {
            var key: ListeningStats.PodcastKey
            var day: Date
        }
        var episodes: [Slot: Set<EpisodeID>] = [:]
        for piece in pieces { episodes[Slot(key: key(piece.record), day: piece.day), default: []].insert(records[piece.record].episode) }
        let seconds = Dictionary(uniqueKeysWithValues: podcastRanking(pieces).map { ($0.key, $0.seconds) })
        let best = episodes.min {
            if $0.value.count != $1.value.count { return $0.value.count > $1.value.count }
            if $0.key.day != $1.key.day { return $0.key.day < $1.key.day }
            if seconds[$0.key.key]! != seconds[$1.key.key]! { return seconds[$0.key.key]! > seconds[$1.key.key]! }
            return title($0.key.key) < title($1.key.key)
        }
        guard let best, best.value.count >= 3 else { return nil }
        return .binge(Binge(podcast: ref(best.key.key), episodes: best.value.count, day: best.key.day))
    }

    func newDiscovery() -> Insight? {
        let ranking = podcastRanking(pieces)
        let candidates = ranking.enumerated().compactMap { offset, entry -> (rank: Int, seconds: TimeInterval, podcast: StatsPodcast)? in
            // Subscribed after recording started: an OPML import at the start is not a discovery.
            guard case let .id(id) = entry.key, let podcast = libraryPodcasts[id], interval.holds(podcast.subscribedAt),
                  let recordingStart, podcast.subscribedAt >= recordingStart, atLeast(entry.seconds, 3_600)
            else { return nil }
            return (offset + 1, entry.seconds, podcast)
        }
        // The ranking is sorted by seconds, so the first candidate is the one with most.
        guard let best = candidates.first else { return nil }
        return .newDiscovery(NewDiscovery(
            podcast: ref(.id(best.podcast.id)), subscribedAt: best.podcast.subscribedAt, rank: best.rank, seconds: best.seconds))
    }
}
