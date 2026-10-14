import Foundation

// E. Listening style (I20–I24).

extension ListeningStats.Context {
    func speed() -> Insight? {
        let average = content / total
        guard abs(average - 1) >= 0.05 - 1e-9 else { return nil }
        let saved = content - total
        let conversion = saved > 0 ? conversion(of: saved, units: ConversionUnit.forSaved) : nil
        return .speed(Speed(average: average, savedSeconds: saved, conversion: conversion))
    }

    func skipped() -> Insight? {
        let seconds = endedRecords.reduce(0) { $0 + records[$1].skippedForwardSeconds }
        guard atLeast(seconds, 600) else { return nil }
        return .skipped(seconds: seconds)
    }

    func completion() -> Insight? {
        let (finished, started) = finishedAndStarted
        let count = finished.count + started.count
        guard count >= 5 else { return nil }
        var lingering: Lingering?
        if containsNow {
            let candidates = library.inProgress.compactMap { episode -> (episode: StatsInProgressEpisode, since: Date)? in
                guard let first = firstSession[episode.id] else { return nil }
                let since = records[first].startedAt
                guard now.timeIntervalSince(since) >= 14 * 86_400 else { return nil }
                return (episode, since)
            }
            if let best = candidates.min(by: {
                $0.since != $1.since ? $0.since < $1.since : $0.episode.title < $1.episode.title
            }) {
                lingering = Lingering(
                    episode: best.episode.id, title: best.episode.title, podcastTitle: best.episode.podcastTitle,
                    position: best.episode.position, since: best.since)
            }
        }
        return .completion(Completion(rate: Double(finished.count) / Double(count), lingering: lingering))
    }

    func sleep() -> Insight? {
        let sessions = endedRecords.filter { records[$0].endReason == .sleepTimer }
        guard sessions.count >= 3 else { return nil }
        var perPodcast: [ListeningStats.PodcastKey: Int] = [:]
        var first: [ListeningStats.PodcastKey: Date] = [:]
        for index in sessions {
            let key = key(index)
            perPodcast[key, default: 0] += 1
            first[key] = min(first[key] ?? .distantFuture, records[index].startedAt)
        }
        let best = perPodcast.min {
            if $0.value != $1.value { return $0.value > $1.value }
            if first[$0.key]! != first[$1.key]! { return first[$0.key]! < first[$1.key]! }
            return title($0.key) < title($1.key)
        }!
        return .sleep(Sleep(count: sessions.count, podcast: ref(best.key), podcastCount: best.value))
    }

    /// Episodes first heard in the period with a valid delay (published → first session).
    var firstHeard: [(record: Int, delay: TimeInterval)] {
        firstSession.values.compactMap { index -> (record: Int, delay: TimeInterval)? in
            let record = records[index]
            guard interval.holds(record.startedAt), record.episodePublishedAt > .distantPast else { return nil }
            let delay = record.startedAt.timeIntervalSince(record.episodePublishedAt)
            return delay >= 0 ? (index, delay) : nil
        }.sorted { records[$0.record].startedAt < records[$1.record].startedAt }
    }

    func freshness() -> Insight? {
        let heard = firstHeard
        guard heard.count >= 5 else { return nil }
        var delays: [PlaylistID?: [TimeInterval]] = [:]
        for entry in heard {
            for (playlist, _) in attributions[entry.record] { delays[playlist, default: []].append(entry.delay) }
        }
        let rows = delays.filter { $0.value.count >= 2 }.map { playlist, values -> PlaylistFreshness in
            let sorted = values.sorted()
            let middle = sorted.count / 2
            let median = sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
            return PlaylistFreshness(playlist: playlist, median: median)
        }.sorted {
            if $0.median != $1.median { return $0.median < $1.median }
            if ($0.playlist == nil) != ($1.playlist == nil) { return $0.playlist != nil }
            return playlistName($0.playlist) < playlistName($1.playlist)
        }
        guard !rows.isEmpty else { return nil }
        return .freshness(rows)
    }
}
