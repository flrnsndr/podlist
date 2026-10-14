import Foundation
import SwiftData

extension SampleData {
    /// About 14 months of listening up to `now` (plan-hoerstatistik §9), deterministic:
    /// a commuter on weekdays, longer weekend mornings, a sleep timer at night, a riser
    /// (Hotel Matze), a podcast that cooled off (Baywatch Berlin), a summer break, faster
    /// speeds over time, and finds like an episode from 2014.
    static func insertListeningSessions(
        into context: ModelContext, now: Date, cast: ListeningCast = .uiTests, calendar: Calendar = .current
    ) throws {
        let library = try context.fetch(FetchDescriptor<Podcast>())
        func shows(_ title: String) -> Show {
            let podcast = library.first { $0.title == title }
            let playlist = podcast?.assignments?.compactMap(\.playlist).first
            return Show(title: title, uuid: podcast?.uuid ?? stableUUID(title.hashValueStable), playlist: playlist?.uuid)
        }
        let lage = shows(cast.daily)
        let matze = shows(cast.riser)
        let methodisch = shows(cast.science)
        let stars = shows(cast.bedtime)
        let history = shows(cast.weekend)
        let baywatch = shows(cast.cooled)
        let flauschig = shows(cast.comedy)

        var random = SampleRandom(seed: 2026)
        var episodeNumber = 0
        func session(_ show: Show, at start: Date, minutes: Double, speed: Double, reason: ListeningEndReason, publishedAgo: TimeInterval) {
            guard start.addingTimeInterval(minutes * 60) <= now else { return }
            episodeNumber += 1
            let listened = minutes * 60
            let session = ListeningSession(episodeUUID: stableUUID(UInt64(episodeNumber)), startedAt: start)
            session.endedAt = start.addingTimeInterval(listened)
            session.listenedSeconds = listened
            session.contentSeconds = listened * speed
            session.skippedForwardSeconds = random.chance(0.3) ? 60 * Double(random.next(in: 1...4)) : 0
            session.endPosition = listened * speed
            session.endReason = reason
            session.podcastUUID = show.uuid
            session.playlistUUID = random.chance(0.5) ? show.playlist : nil
            session.episodeTitle = "\(show.title) \(episodeNumber)"
            session.podcastTitle = show.title
            session.episodePublishedAt = start.addingTimeInterval(-publishedAgo)
            session.episodeDuration = listened * speed
            context.insert(session)
        }

        let today = calendar.startOfDay(for: now)
        let firstMonth = calendar.date(byAdding: .month, value: -13, to: calendar.dateInterval(of: .month, for: today)!.start)!
        var day = firstMonth
        var index = 0
        while day <= today {
            defer {
                day = calendar.date(byAdding: .day, value: 1, to: day)!
                index += 1
            }
            let month = calendar.component(.month, from: day)
            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            // A summer break and a few quiet days.
            if month == 8, (10...19).contains(calendar.component(.day, from: day)) { continue }
            if random.chance(0.12) { continue }
            // Months from the start: Hotel Matze rises, Baywatch Berlin cools off, speed grows.
            let progress = Double(index) / 420
            let speed = 1.2 + 0.3 * progress
            func at(_ hour: Int, _ minute: Int) -> Date {
                calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
            }
            // Hotel Matze grows steadily; Baywatch Berlin is big in the first half, then gone.
            func pick() -> Show {
                let roll = random.unit()
                let matzeShare = 0.05 + 0.75 * progress
                let baywatchShare = progress < 0.55 ? 0.5 : 0.02
                if roll < matzeShare { return matze }
                if roll < matzeShare + baywatchShare { return baywatch }
                if roll < matzeShare + baywatchShare + 0.15 { return random.chance(0.5) ? flauschig : methodisch }
                return lage
            }

            if isWeekend {
                session(history, at: at(9, 30 + random.next(in: 0...20)), minutes: Double(random.next(in: 45...110)), speed: speed,
                        reason: .finished, publishedAgo: 86_400 * Double(random.next(in: 2...60)))
                if random.chance(0.6) {
                    session(pick(), at: at(15, random.next(in: 0...40)), minutes: Double(random.next(in: 30...60)), speed: speed,
                            reason: .paused, publishedAgo: 86_400 * Double(random.next(in: 1...20)))
                }
            } else {
                session(random.chance(0.5) ? lage : pick(), at: at(7, 10 + random.next(in: 0...15)), minutes: Double(random.next(in: 30...45)), speed: speed,
                        reason: random.chance(0.6) ? .finished : .paused, publishedAgo: 3_600 * Double(random.next(in: 2...30)))
                session(pick(), at: at(17, 30 + random.next(in: 0...20)), minutes: Double(random.next(in: 25...40)), speed: speed,
                        reason: random.chance(0.5) ? .finished : .paused, publishedAgo: 86_400 * Double(random.next(in: 1...30)))
            }
            if random.chance(0.2) {
                session(stars, at: at(23, random.next(in: 0...40)), minutes: Double(random.next(in: 12...25)), speed: 1,
                        reason: .sleepTimer, publishedAgo: 86_400 * Double(random.next(in: 5...400)))
            }
        }

        // Finds: an episode from 2014 and a long night.
        let archive = calendar.date(byAdding: .day, value: -20, to: today)!
        session(history, at: calendar.date(bySettingHour: 20, minute: 0, second: 0, of: archive)!, minutes: 70, speed: 1.3,
                reason: .finished, publishedAgo: archive.timeIntervalSince(calendar.date(from: DateComponents(year: 2014, month: 3, day: 12))!))
        let night = calendar.date(byAdding: .day, value: -12, to: today)!
        session(stars, at: calendar.date(bySettingHour: 2, minute: 41, second: 0, of: night)!, minutes: 30, speed: 1,
                reason: .sleepTimer, publishedAgo: 86_400 * 3)
        try context.save()
    }

    /// The podcasts the listening log is about, by their role in it.
    struct ListeningCast {
        var daily: String
        var riser: String
        var science: String
        var bedtime: String
        var weekend: String
        var cooled: String
        var comedy: String

        static let uiTests = ListeningCast(
            daily: "Lage der Nation", riser: "Hotel Matze", science: "Methodisch inkorrekt", bedtime: "Sternengeschichten",
            weekend: "Geschichten aus der Geschichte", cooled: "Baywatch Berlin", comedy: "Fest & Flauschig")
    }

    private struct Show {
        var title: String
        var uuid: UUID
        var playlist: UUID?
    }

    private static func stableUUID(_ number: UInt64) -> UUID {
        UUID(uuidString: String(format: "5A3D1E00-0000-4000-8000-%012llX", number & 0xFFFF_FFFF_FFFF))!
    }
}

/// SplitMix64: the same numbers on every run.
private struct SampleRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(nextUInt64() >> 11) / Double(1 << 53) }
    mutating func chance(_ probability: Double) -> Bool { unit() < probability }
    mutating func next(in range: ClosedRange<Int>) -> Int { range.lowerBound + Int(nextUInt64() % UInt64(range.count)) }
}

private extension String {
    /// `hashValue` changes per launch; this does not.
    var hashValueStable: UInt64 {
        utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}
