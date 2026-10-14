import Foundation

// H. Developments over time (I29–I36).

extension ListeningStats.Context {
    private typealias Shares = [ListeningStats.PodcastKey: Double]

    private func podcastShares(_ pieces: [ListeningStats.Piece]) -> Shares? {
        let sum = pieces.reduce(0) { $0 + $1.listened }
        guard sum > 0 else { return nil }
        var shares: Shares = [:]
        for piece in pieces { shares[key(piece.record), default: 0] += piece.listened / sum }
        return shares
    }

    private func average<Key: Hashable>(_ months: [[Key: Double]]) -> [Key: Double] {
        var result: [Key: Double] = [:]
        for month in months { for (key, share) in month { result[key, default: 0] += share / Double(months.count) } }
        return result
    }

    func trend() -> Insight? {
        switch period.kind {
        case .month:
            guard listeningDays.count >= 3 else { return nil }
            let bars = periodDays.map { TrendBar(start: $0, seconds: dayTotals[$0] ?? 0) }
            return .trend(Trend(bars: bars, average: total / Double(bars.count)))
        case .year:
            let months = dataMonths
            guard months.count >= 2 else { return nil }
            var starts: [Date] = []
            for day in periodDays where starts.last != monthStart(day) { starts.append(monthStart(day)) }
            let perMonth = Dictionary(uniqueKeysWithValues: months.map { ($0.month, $0.pieces.reduce(0) { $0 + $1.listened }) })
            let bars = starts.map { TrendBar(start: $0, seconds: perMonth[$0] ?? 0) }
            return .trend(Trend(bars: bars, average: total / Double(bars.count)))
        }
    }

    /// The "from" and "to" sides of I30/I31 and the months the line chart shows.
    private var shareComparison: (from: Shares, to: Shares, shown: [(month: Date, shares: Shares)])? {
        switch period.kind {
        case .month:
            var earlier: [(month: Date, shares: Shares)] = []
            var previous = period.previous
            for _ in 0 ..< 3 {
                let range = previous.interval(in: calendar)
                if let shares = podcastShares(pieces(in: range)) { earlier.append((range.start, shares)) }
                previous = previous.previous
            }
            guard earlier.count >= 2, let current = podcastShares(pieces) else { return nil }
            earlier.reverse()
            return (average(earlier.map(\.shares)), current, earlier + [(interval.start, current)])
        case .year:
            let months = dataMonths.compactMap { entry in podcastShares(entry.pieces).map { (month: entry.month, shares: $0) } }
            guard months.count >= 3 else { return nil }
            let third = max(1, months.count / 3)
            return (average(months.prefix(third).map(\.shares)), average(months.suffix(third).map(\.shares)), months)
        }
    }

    private func ranked(_ shares: Shares) -> [ListeningStats.PodcastKey] {
        shares.filter { $0.value > 0 }.keys.sorted {
            shares[$0]! != shares[$1]! ? shares[$0]! > shares[$1]! : title($0) < title($1)
        }
    }

    private func change(for key: ListeningStats.PodcastKey, _ comparison: (from: Shares, to: Shares, shown: [(month: Date, shares: Shares)])) -> ShareChange {
        let fromRanking = ranked(comparison.from)
        let toRanking = ranked(comparison.to)
        return ShareChange(
            podcast: ref(key), fromShare: comparison.from[key] ?? 0, toShare: comparison.to[key] ?? 0,
            fromRank: (fromRanking.firstIndex(of: key) ?? fromRanking.count) + 1,
            toRank: toRanking.firstIndex(of: key).map { $0 + 1 },
            monthly: comparison.shown.map { MonthValue(month: $0.month, value: $0.shares[key] ?? 0) })
    }

    func riser() -> Insight? {
        guard let comparison = shareComparison else { return nil }
        let keys = Set(comparison.from.keys).union(comparison.to.keys)
        func delta(_ key: ListeningStats.PodcastKey) -> Double { (comparison.to[key] ?? 0) - (comparison.from[key] ?? 0) }
        guard let best = keys.min(by: {
            if abs(delta($0) - delta($1)) > 1e-12 { return delta($0) > delta($1) }
            return title($0) < title($1)
        }), delta(best) >= 0.10 - 1e-9 else { return nil }
        return .riser(change(for: best, comparison))
    }

    func cooled() -> Insight? {
        guard let comparison = shareComparison else { return nil }
        func delta(_ key: ListeningStats.PodcastKey) -> Double { (comparison.from[key] ?? 0) - (comparison.to[key] ?? 0) }
        guard let best = ranked(comparison.from).prefix(3).min(by: {
            if abs(delta($0) - delta($1)) > 1e-12 { return delta($0) > delta($1) }
            return title($0) < title($1)
        }), delta(best) >= 0.10 - 1e-9 else { return nil }
        return .cooled(change(for: best, comparison))
    }

    func playlistShift() -> Insight? {
        guard period.kind == .year else { return nil }
        let months = dataMonths
        guard months.count >= 3 else { return nil }
        let perMonth = months.map { entry -> (month: Date, seconds: [PlaylistID?: TimeInterval]) in
            (entry.month, playlistSeconds(entry.pieces))
        }
        let shares = perMonth.map { entry -> [PlaylistID?: Double] in
            let sum = entry.seconds.values.reduce(0, +)
            return entry.seconds.mapValues { $0 / sum }
        }
        // Every month has every playlist of the year (0 where unheard), in one order: biggest
        // over the year first, so the stacked areas never swap or leave gaps.
        var yearSeconds: [PlaylistID?: TimeInterval] = [:]
        for entry in perMonth { for (playlist, seconds) in entry.seconds { yearSeconds[playlist, default: 0] += seconds } }
        let order = sortedPlaylists(yearSeconds).map(\.playlist)
        let result = zip(perMonth, shares).map { entry, monthShares in
            PlaylistMonth(
                month: entry.month,
                shares: order.map {
                    PlaylistShare(playlist: $0, seconds: entry.seconds[$0] ?? 0, share: monthShares[$0] ?? 0)
                })
        }
        let third = max(1, months.count / 3)
        let from = average(Array(shares.prefix(third)))
        let to = average(Array(shares.suffix(third)))
        let growth = to.compactMap { playlist, share -> (playlist: PlaylistID?, factor: Double)? in
            // Named only when it matters now: 1 % → 4 % is no trend.
            guard let before = from[playlist], before > 0, share / before >= 2 - 1e-9, share >= 0.1 - 1e-9 else { return nil }
            return (playlist, share / before)
        }.min {
            if abs($0.factor - $1.factor) > 1e-12 { return $0.factor > $1.factor }
            return playlistName($0.playlist) < playlistName($1.playlist)
        }
        let highlight = growth.map {
            PlaylistGrowth(playlist: $0.playlist, since: months[months.count - third].month, factor: $0.factor)
        }
        return .playlistShift(PlaylistShift(months: result, highlight: highlight))
    }

    func speedTrend() -> Insight? {
        guard period.kind == .year else { return nil }
        let months = dataMonths
        guard months.count >= 3 else { return nil }
        let monthly = months.map { entry in
            MonthValue(
                month: entry.month,
                value: entry.pieces.reduce(0) { $0 + $1.content } / entry.pieces.reduce(0) { $0 + $1.listened })
        }
        guard abs(monthly.last!.value - monthly.first!.value) >= 0.1 - 1e-9 else { return nil }
        return .speedTrend(SpeedTrend(monthly: monthly))
    }

    func daytimeShift() -> Insight? {
        guard period.kind == .year else { return nil }
        let months = dataMonths
        guard months.count >= 3 else { return nil }
        func dominant(_ slice: ArraySlice<(month: Date, pieces: [ListeningStats.Piece])>) -> DayPart {
            var seconds: [DayPart: TimeInterval] = [:]
            for entry in slice { for piece in entry.pieces { seconds[dayPart(piece.hour), default: 0] += piece.listened } }
            return DayPart.allCases.max { (seconds[$0] ?? 0) < (seconds[$1] ?? 0) } ?? .morning
        }
        let half = months.count / 2
        let from = dominant(months.prefix(half)[...])
        let to = dominant(months.suffix(half)[...])
        return from == to ? nil : .daytimeShift(from: from, to: to)
    }

    func yearChapters() -> Insight? {
        guard period.kind == .year else { return nil }
        let months = dataMonths
        guard months.count >= 3 else { return nil }
        return .yearChapters(months.compactMap { entry in
            podcastRanking(entry.pieces).first.map { MonthTop(month: entry.month, podcast: ref($0.key)) }
        })
    }

    func newVsLoyal() -> Insight? {
        guard period.kind == .year else { return nil }
        let previousPieces = pieces(in: period.previous.interval(in: calendar))
        let previousRanking = podcastRanking(previousPieces)
        guard !previousRanking.isEmpty else { return nil }
        let top = podcastRanking(pieces).prefix(5).map(\.key)
        let previousTop = Set(previousRanking.prefix(5).map(\.key))
        let heardBefore = Set(previousRanking.map(\.key))
        return .newVsLoyal(
            newInTop: top.filter { !heardBefore.contains($0) }.count,
            loyal: top.filter { previousTop.contains($0) }.map(ref))
    }
}
