import Foundation

// D. Rhythm and patterns (I17–I19).

extension ListeningStats.Context {
    private static let partHours: [DayPart: Double] = [.morning: 6, .midday: 3, .afternoon: 4, .evening: 4, .night: 7]

    private var hasRhythm: Bool { atLeast(total, 5 * 3_600) && listeningDays.count >= 5 }

    private var grid: [[TimeInterval]] {
        var grid = Array(repeating: Array(repeating: 0.0, count: 24), count: 7)
        for piece in pieces { grid[piece.weekday - 1][piece.hour] += piece.listened }
        return grid
    }

    /// Share of the period's listening on `weekdays` (Calendar numbering) within `hours`.
    private func share(_ grid: [[TimeInterval]], weekdays: [Int], hours: [Int]) -> Double {
        var sum = 0.0
        for weekday in weekdays { for hour in hours { sum += grid[weekday - 1][hour] } }
        return sum / total
    }

    func heatmap() -> Insight? {
        guard hasRhythm else { return nil }
        let grid = grid
        var best: (weekend: Bool, part: DayPart, value: Double)?
        for weekend in [false, true] {
            for part in DayPart.allCases {
                let weekdays = weekend ? [1, 7] : [2, 3, 4, 5, 6]
                var sum = 0.0
                for weekday in weekdays { for hour in 0 ..< 24 where dayPart(hour) == part { sum += grid[weekday - 1][hour] } }
                let value = sum / (Double(weekdays.count) * Self.partHours[part]!)
                if best == nil || value > best!.value + 1e-9 { best = (weekend, part, value) }
            }
        }
        return .heatmap(Heatmap(seconds: grid, peakIsWeekend: best!.weekend, peakPart: best!.part))
    }

    func listenerType() -> Insight? {
        guard hasRhythm else { return nil }
        let grid = grid
        let workdays = [2, 3, 4, 5, 6]
        let all = Array(1 ... 7)
        let morning = share(grid, weekdays: workdays, hours: Array(6 ..< 10))
        let evening = share(grid, weekdays: workdays, hours: Array(15 ..< 20))
        let weekend = share(grid, weekdays: [1, 7], hours: Array(0 ..< 24))
        let tolerance = 1e-9

        let type: ListenerType
        var typeShare: Double
        let night = share(grid, weekdays: all, hours: [22, 23, 0, 1, 2, 3])
        let early = share(grid, weekdays: all, hours: [5, 6, 7])
        let lunch = share(grid, weekdays: all, hours: [12, 13])
        let afterWork = share(grid, weekdays: all, hours: Array(18 ..< 22))
        if morning >= 0.10 - tolerance, evening >= 0.10 - tolerance, morning + evening >= 0.40 - tolerance, weekend < 0.20 {
            (type, typeShare) = (.commuter, morning + evening)
        } else if night >= 0.30 - tolerance {
            (type, typeShare) = (.nightOwl, night)
        } else if early >= 0.30 - tolerance {
            (type, typeShare) = (.earlyBird, early)
        } else if weekend >= 0.45 - tolerance {
            (type, typeShare) = (.weekender, weekend)
        } else if lunch >= 0.25 - tolerance {
            (type, typeShare) = (.lunchBreak, lunch)
        } else if afterWork >= 0.35 - tolerance {
            (type, typeShare) = (.afterWork, afterWork)
        } else {
            var parts: [DayPart: Double] = [:]
            for hour in 0 ..< 24 { parts[dayPart(hour), default: 0] += share(grid, weekdays: all, hours: [hour]) }
            (type, typeShare) = (.allRounder, parts.values.max() ?? 0)
        }

        let spice: ListenerSpice?
        let sessions = endedRecords.count
        if content / total >= 1.5 - tolerance {
            spice = .fast
        } else if let run = longestRun(), atLeast(run.seconds, 2 * 3_600) {
            spice = .stamina
        } else if sessions > 0,
                  Double(endedRecords.filter { records[$0].endReason == .sleepTimer }.count) / Double(sessions) >= 0.20 - tolerance
        {
            spice = .sleeper
        } else {
            spice = nil
        }
        return .listenerType(ListenerProfile(type: type, spice: spice, share: typeShare))
    }

    func favoriteWeekday() -> Insight? {
        guard Set(pieces.map { weekStart($0.day) }).count >= 2 else { return nil }
        var perWeekday = [Int: TimeInterval]()
        for piece in pieces { perWeekday[piece.weekday, default: 0] += piece.listened }
        let best = perWeekday.min { abs($0.value - $1.value) > 1e-9 ? $0.value > $1.value : $0.key < $1.key }!
        let weekend = (perWeekday[1] ?? 0) + (perWeekday[7] ?? 0)
        return .favoriteWeekday(weekday: best.key, weekendShare: weekend / total)
    }
}
