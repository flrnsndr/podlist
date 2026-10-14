import Foundation

// C. Records (I13–I16).

extension ListeningStats.Context {
    func recordDay() -> Insight? {
        guard listeningDays.count >= 2 else { return nil }
        let best = dayTotals.filter { $0.value > 0 }.min {
            abs($0.value - $1.value) > 1e-9 ? $0.value > $1.value : $0.key < $1.key
        }!
        let dayPieces = pieces.filter { $0.day == best.key }
        guard let topPodcast = podcastRanking(dayPieces).first, let topPlaylist = sortedPlaylists(playlistSeconds(dayPieces)).first
        else { return nil }
        return .recordDay(RecordDay(
            day: best.key, seconds: best.value, topPodcast: ref(topPodcast.key), topPlaylist: topPlaylist.playlist))
    }

    func streak() -> Insight? {
        let days = listeningDays
        var longest = 0
        var longestStart = Date.distantPast
        var runStart: Date?
        var length = 0
        var previous: Date?
        for day in days {
            if let previous, nextDay(previous) == day {
                length += 1
            } else {
                runStart = day
                length = 1
            }
            if length > longest {
                longest = length
                longestStart = runStart!
            }
            previous = day
        }

        var current: Int?
        if containsNow {
            let all = Set(allPieces.map(\.day))
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            var day: Date? = all.contains(today) ? today : all.contains(yesterday) ? yesterday : nil
            var count = 0
            var currentStart = today
            while let d = day, all.contains(d) {
                count += 1
                currentStart = d
                day = calendar.date(byAdding: .day, value: -1, to: d)
            }
            current = count >= 1 ? count : nil
            // A run that began before the period is still the longest one shown next to it.
            if count > longest {
                longest = count
                longestStart = currentStart
            }
        }
        guard longest >= 3 else { return nil }
        return .streak(Streak(longest: longest, longestStart: longestStart, current: current))
    }

    func longestBreak() -> Insight? {
        guard period.kind == .year else { return nil }
        let days = listeningDays
        guard let first = days.first else { return nil }
        var best = 0
        var bestStart = first
        func consider(from last: Date, to next: Date) {
            let gap = daysBetween(last, next) - 1
            if gap > best {
                best = gap
                bestStart = nextDay(last)
            }
        }
        for (previous, day) in zip(days, days.dropFirst()) { consider(from: previous, to: day) }
        if containsNow, let last = days.last { consider(from: last, to: today) }
        guard best >= 7 else { return nil }
        return .longestBreak(days: best, start: bestStart)
    }

    func strongestStretch() -> Insight? {
        var groups: [Date: TimeInterval] = [:]
        for piece in pieces {
            let start: Date
            switch period.kind {
            case .month: start = max(weekStart(piece.day), interval.start)
            case .year: start = monthStart(piece.day)
            }
            groups[start, default: 0] += piece.listened
        }
        guard groups.count >= 2 else { return nil }
        let best = groups.min { abs($0.value - $1.value) > 1e-9 ? $0.value > $1.value : $0.key < $1.key }!
        return .strongestStretch(StrongestStretch(start: best.key, seconds: best.value))
    }
}
