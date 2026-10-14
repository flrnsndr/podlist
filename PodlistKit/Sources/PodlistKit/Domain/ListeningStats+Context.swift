import Foundation

// Shared groundwork of the evaluation: a session is cut into pieces at every hour boundary
// of the device calendar and its listening time is spread over them in proportion to the
// wall-clock span (plan §5). Days, hours, weekdays and periods are then read off the pieces.

extension ListeningStats {
    enum PodcastKey: Hashable {
        case id(PodcastID)
        case title(String)
    }

    /// The part of a session that lies in one hour.
    struct Piece {
        var record: Int
        var start: Date
        var end: Date
        var listened: TimeInterval
        var content: TimeInterval
        var day: Date
        var hour: Int
        var weekday: Int
    }

    struct Context {
        let period: StatsPeriod
        let interval: DateInterval
        let calendar: Calendar
        let now: Date
        let library: StatsLibrary
        let records: [ListeningRecord]
        /// Pieces of the whole log (earlier periods, streaks across the period start).
        let allPieces: [Piece]
        /// Pieces inside the period.
        let pieces: [Piece]
        let containsNow: Bool
        let today: Date
        let total: TimeInterval
        let content: TimeInterval
        /// Most recent stored title per podcast.
        let titles: [PodcastKey: String]
        let attributions: [[(playlist: PlaylistID?, weight: Double)]]
        let libraryPodcasts: [PodcastID: StatsPodcast]
        /// Records whose session ended in the period (what counts as "a session of the period").
        let endedRecords: [Int]
        /// The first session ever per episode (index into `records`).
        let firstSession: [EpisodeID: Int]
        /// The first session ever.
        let recordingStart: Date?
        /// Days of the period since recording started, up to today in the current period.
        let periodDays: [Date]
        let dayTotals: [Date: TimeInterval]

        init(period: StatsPeriod, records: [ListeningRecord], library: StatsLibrary, calendar: Calendar, now: Date) {
            self.period = period
            self.calendar = calendar
            self.now = now
            self.library = library
            self.records = records
            interval = period.interval(in: calendar)
            containsNow = interval.holds(now)
            today = calendar.startOfDay(for: now)

            let all = Self.pieces(of: records, calendar: calendar)
            allPieces = all
            let interval = interval
            let inPeriod = all.filter { interval.holds($0.start) }
            pieces = inPeriod
            total = inPeriod.reduce(0) { $0 + $1.listened }
            content = inPeriod.reduce(0) { $0 + $1.content }

            var titles: [PodcastKey: String] = [:]
            var latest: [PodcastKey: Date] = [:]
            for record in records {
                let key = Self.key(of: record)
                if let seen = latest[key], seen > record.startedAt { continue }
                latest[key] = record.startedAt
                titles[key] = record.podcastTitle
            }
            self.titles = titles

            let podcasts = Dictionary(library.podcasts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            libraryPodcasts = podcasts
            attributions = records.map { Self.attribution(of: $0, podcasts: podcasts) }
            endedRecords = records.indices.filter { interval.holds(records[$0].endedAt) }

            var first: [EpisodeID: Int] = [:]
            for index in records.indices {
                if let existing = first[records[index].episode], records[existing].startedAt <= records[index].startedAt { continue }
                first[records[index].episode] = index
            }
            firstSession = first

            // Days before the recording started are not "days without listening" (plan §6.3, N58).
            var days: [Date] = []
            recordingStart = records.map(\.startedAt).min()
            var day = max(interval.start, recordingStart.map { calendar.startOfDay(for: $0) } ?? interval.start)
            let end = containsNow
                ? min(interval.end, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!)
                : interval.end
            while day < end {
                days.append(day)
                day = calendar.date(byAdding: .day, value: 1, to: day)!
            }
            periodDays = days
            var totals: [Date: TimeInterval] = [:]
            for piece in inPeriod { totals[piece.day, default: 0] += piece.listened }
            dayTotals = totals
        }

        // MARK: Pieces

        static func pieces(of records: [ListeningRecord], calendar: Calendar) -> [Piece] {
            var result: [Piece] = []
            for (index, record) in records.enumerated() where record.listenedSeconds > 0 {
                let span = record.endedAt.timeIntervalSince(record.startedAt)
                guard span > 0 else {
                    result.append(piece(index, record.startedAt, record.startedAt, record.listenedSeconds, record.contentSeconds, calendar))
                    continue
                }
                var cursor = record.startedAt
                while cursor < record.endedAt {
                    var end = calendar.dateInterval(of: .hour, for: cursor)?.end ?? record.endedAt
                    if end <= cursor || end > record.endedAt { end = record.endedAt }
                    let fraction = end.timeIntervalSince(cursor) / span
                    result.append(piece(index, cursor, end, record.listenedSeconds * fraction, record.contentSeconds * fraction, calendar))
                    cursor = end
                }
            }
            return result
        }

        private static func piece(
            _ index: Int, _ start: Date, _ end: Date, _ listened: TimeInterval, _ content: TimeInterval, _ calendar: Calendar
        ) -> Piece {
            Piece(
                record: index, start: start, end: end, listened: listened, content: content,
                day: calendar.startOfDay(for: start), hour: calendar.component(.hour, from: start),
                weekday: calendar.component(.weekday, from: start))
        }

        // MARK: Identity and attribution

        static func key(of record: ListeningRecord) -> PodcastKey {
            record.podcast.map { .id($0) } ?? .title(record.podcastTitle)
        }

        func key(_ record: Int) -> PodcastKey { Self.key(of: records[record]) }

        func ref(_ key: PodcastKey) -> PodcastRef {
            switch key {
            case let .id(id): PodcastRef(id: id, title: titles[key] ?? libraryPodcasts[id]?.title ?? "")
            case let .title(title): PodcastRef(id: nil, title: title)
            }
        }

        func ref(ofRecord record: Int) -> PodcastRef { ref(key(record)) }

        func title(_ key: PodcastKey) -> String { ref(key).title }

        /// Plan §5: the block it played in, else the podcast's playlists in equal parts, else none.
        static func attribution(
            of record: ListeningRecord, podcasts: [PodcastID: StatsPodcast]
        ) -> [(playlist: PlaylistID?, weight: Double)] {
            if let playlist = record.playlist { return [(playlist, 1)] }
            if let id = record.podcast, let podcast = podcasts[id] {
                var seen = Set<PlaylistID>()
                let playlists = podcast.playlists.filter { seen.insert($0).inserted }
                if !playlists.isEmpty { return playlists.map { ($0, 1 / Double(playlists.count)) } }
            }
            return [(nil, 1)]
        }

        func playlistName(_ id: PlaylistID?) -> String {
            guard let id else { return "" }
            return library.playlists.first { $0.id == id }?.name ?? id.uuid.uuidString
        }

        func playlistSeconds(_ pieces: [Piece]) -> [PlaylistID?: TimeInterval] {
            var result: [PlaylistID?: TimeInterval] = [:]
            for piece in pieces {
                for (playlist, weight) in attributions[piece.record] { result[playlist, default: 0] += piece.listened * weight }
            }
            return result
        }

        /// Most seconds first; ties by name, "Ohne Playlist" last.
        func sortedPlaylists(_ seconds: [PlaylistID?: TimeInterval]) -> [(playlist: PlaylistID?, seconds: TimeInterval)] {
            seconds.map { (playlist: $0.key, seconds: $0.value) }.sorted {
                if abs($0.seconds - $1.seconds) > 1e-9 { return $0.seconds > $1.seconds }
                if ($0.playlist == nil) != ($1.playlist == nil) { return $0.playlist != nil }
                return playlistName($0.playlist) < playlistName($1.playlist)
            }
        }

        /// Most seconds first, then the one heard first, then by title.
        func podcastRanking(_ pieces: [Piece]) -> [(key: PodcastKey, seconds: TimeInterval)] {
            var seconds: [PodcastKey: TimeInterval] = [:]
            var first: [PodcastKey: Date] = [:]
            for piece in pieces {
                let key = key(piece.record)
                seconds[key, default: 0] += piece.listened
                if let seen = first[key], seen <= piece.start { continue }
                first[key] = piece.start
            }
            return seconds.map { (key: $0.key, seconds: $0.value) }.sorted {
                if abs($0.seconds - $1.seconds) > 1e-9 { return $0.seconds > $1.seconds }
                if first[$0.key]! != first[$1.key]! { return first[$0.key]! < first[$1.key]! }
                return title($0.key) < title($1.key)
            }
        }

        // MARK: Calendar helpers

        func seconds(in interval: DateInterval) -> TimeInterval {
            allPieces.reduce(0) { interval.holds($1.start) ? $0 + $1.listened : $0 }
        }

        func pieces(in interval: DateInterval) -> [Piece] {
            allPieces.filter { interval.holds($0.start) }
        }

        func nextDay(_ day: Date) -> Date { calendar.date(byAdding: .day, value: 1, to: day)! }

        func monthStart(_ date: Date) -> Date { calendar.dateInterval(of: .month, for: date)!.start }

        func weekStart(_ date: Date) -> Date { calendar.dateInterval(of: .weekOfYear, for: date)!.start }

        func daysBetween(_ from: Date, _ to: Date) -> Int {
            calendar.dateComponents([.day], from: from, to: to).day ?? 0
        }

        var listeningDays: [Date] { dayTotals.filter { $0.value > 0 }.keys.sorted() }

        /// Months of the period that have listening, oldest first, with their pieces.
        var dataMonths: [(month: Date, pieces: [Piece])] {
            Dictionary(grouping: pieces) { monthStart($0.day) }
                .map { (month: $0.key, pieces: $0.value) }.sorted { $0.month < $1.month }
        }

        func dayPart(_ hour: Int) -> DayPart {
            switch hour {
            case 5 ..< 11: .morning
            case 11 ..< 14: .midday
            case 14 ..< 18: .afternoon
            case 18 ..< 22: .evening
            default: .night
            }
        }

        func moment(record: Int, date: Date) -> EpisodeMoment {
            EpisodeMoment(
                episode: records[record].episode, title: records[record].episodeTitle, podcast: ref(ofRecord: record),
                date: date)
        }

        /// Time thresholds tolerate the rounding of proportional splits.
        func atLeast(_ value: Double, _ threshold: Double) -> Bool { value >= threshold - 1e-6 }

        func atMost(_ value: Double, _ threshold: Double) -> Bool { value <= threshold + 1e-6 }

        /// Picks one of `units` by the period's seed whose count is 2…99 (plan §6.2).
        func conversion(of seconds: TimeInterval, units: [ConversionUnit]) -> Conversion? {
            let candidates = units.compactMap { unit -> Conversion? in
                let count = Int(seconds / unit.seconds + 1e-9)
                return (2 ... 99).contains(count) ? Conversion(unit: unit, count: count) : nil
            }
            guard !candidates.isEmpty else { return nil }
            return candidates[Int(period.seed % UInt64(candidates.count))]
        }
    }
}

extension DateInterval {
    /// Start inclusive, end exclusive (`contains` includes the end).
    func holds(_ date: Date) -> Bool { date >= start && date < end }
}
