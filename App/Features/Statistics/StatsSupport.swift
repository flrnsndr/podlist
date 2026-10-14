import PodlistKit
import SwiftUI

/// What the statistics cards need to show playlists and podcasts by their IDs: today's
/// playlists (name, color, symbol) and artwork. Playlists that were deleted since still
/// count, with a neutral name (plan-hoerstatistik §5).
struct StatsLookup {
    var playlists: [PlaylistID: Playlist] = [:]
    var artwork: [PodcastID: URL] = [:]
    /// The podcast's first playlist: its symbol stands in for a missing cover (plan §8).
    var podcastPlaylist: [PodcastID: PlaylistID] = [:]

    init(playlists: [Playlist], podcasts: [Podcast]) {
        self.playlists = Dictionary(playlists.map { ($0.playlistID, $0) }, uniquingKeysWith: { first, _ in first })
        artwork = Dictionary(
            podcasts.compactMap { podcast in podcast.artworkURL.map { (PodcastID(podcast.uuid), $0) } },
            uniquingKeysWith: { first, _ in first })
        podcastPlaylist = Dictionary(
            podcasts.compactMap { podcast in
                podcast.assignments?.compactMap(\.playlist).min { $0.displayOrder < $1.displayOrder }
                    .map { (PodcastID(podcast.uuid), $0.playlistID) }
            },
            uniquingKeysWith: { first, _ in first })
    }

    init() {}

    func name(of playlist: PlaylistID?) -> String {
        guard let playlist else { return String(localized: "Without Playlist") }
        return playlists[playlist]?.displayName ?? String(localized: "Deleted Playlist")
    }

    func color(of playlist: PlaylistID?) -> Color {
        playlist.flatMap { playlists[$0]?.color } ?? .gray
    }

    func symbol(of playlist: PlaylistID?) -> String {
        guard let playlist else { return "tray" }
        return playlists[playlist]?.symbolName ?? "questionmark.folder"
    }

    func playlist(of podcast: PodcastRef) -> PlaylistID? {
        podcast.id.flatMap { podcastPlaylist[$0] }
    }

    func artworkURL(of podcast: PodcastRef) -> URL? {
        podcast.id.flatMap { artwork[$0] }
    }
}

/// A playlist's symbol on its color for statistics (works for "Without Playlist" too).
struct StatsPlaylistIcon: View {
    let playlist: PlaylistID?
    let lookup: StatsLookup
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: lookup.symbol(of: playlist))
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(lookup.color(of: playlist).gradient, in: .rect(cornerRadius: size * 0.25))
            .accessibilityHidden(true)
    }
}

// MARK: Formatting

extension StatsPeriod {
    /// "October 2026" / "Oktober 2026", or "2026".
    func title(in calendar: Calendar) -> String {
        switch self {
        case .month: interval(in: calendar).start.formatted(.dateTime.month(.wide).year())
        case let .year(year): String(year)
        }
    }
}

extension TimeInterval {
    /// "23 days" / "23 Tage", "1 day" / "1 Tag".
    static func daysText(_ days: Int) -> String {
        Duration.seconds(Double(days) * 86_400).formatted(.units(allowed: [.days], width: .wide))
    }

    /// The largest fitting unit: "3 hr" / "41 days" (I24, I37).
    var roughText: String {
        Duration.seconds(self).formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 1))
    }
}

extension Double {
    /// "23 %" / "23%".
    var percentText: String { formatted(.percent.precision(.fractionLength(0))) }
}

extension Date {
    /// "Saturday, 18 October" / "Samstag, 18. Oktober".
    var dayText: String { formatted(.dateTime.weekday(.wide).day().month(.wide)) }
    /// "18 October" / "18. Oktober".
    var shortDayText: String { formatted(.dateTime.day().month(.wide)) }
    /// "March 2014" / "März 2014".
    var monthText: String { formatted(.dateTime.month(.wide).year()) }
}

extension DayPart {
    /// "in the morning" / "morgens".
    var adverb: String {
        switch self {
        case .morning: String(localized: "in the morning")
        case .midday: String(localized: "at lunchtime")
        case .afternoon: String(localized: "in the afternoon")
        case .evening: String(localized: "in the evening")
        case .night: String(localized: "at night")
        }
    }

    /// "on weekend mornings" / "am Wochenende morgens".
    func phrase(weekend: Bool) -> String {
        switch (weekend, self) {
        case (false, .morning): String(localized: "on weekday mornings")
        case (false, .midday): String(localized: "at lunchtime on weekdays")
        case (false, .afternoon): String(localized: "on weekday afternoons")
        case (false, .evening): String(localized: "on weekday evenings")
        case (false, .night): String(localized: "at night on weekdays")
        case (true, .morning): String(localized: "on weekend mornings")
        case (true, .midday): String(localized: "at lunchtime on weekends")
        case (true, .afternoon): String(localized: "on weekend afternoons")
        case (true, .evening): String(localized: "on weekend evenings")
        case (true, .night): String(localized: "at night on weekends")
        }
    }
}

extension ListenerProfile {
    /// "Night Owl at Full Speed" / "Nachteule im Schnellgang".
    var title: String {
        let name = switch type {
        case .commuter: String(localized: "Commuter")
        case .nightOwl: String(localized: "Night Owl")
        case .earlyBird: String(localized: "Early Bird")
        case .weekender: String(localized: "Weekend Listener")
        case .lunchBreak: String(localized: "Lunch Break Listener")
        case .afterWork: String(localized: "After-Work Listener")
        case .allRounder: String(localized: "Always Ready")
        }
        guard let spice else { return name }
        let suffix = switch spice {
        case .fast: String(localized: "at Full Speed")
        case .stamina: String(localized: "with Staying Power")
        case .sleeper: String(localized: "Who Dozes Off")
        }
        return "\(name) \(suffix)"
    }

    var detail: String {
        let share = share.percentText
        return switch type {
        case .commuter: String(localized: "Peaks in the morning and evening, Monday to Friday.")
        case .nightOwl: String(localized: "\(share) of your listening after 10 pm.")
        case .earlyBird: String(localized: "\(share) of your listening between 5 and 8 am.")
        case .weekender: String(localized: "\(share) of your listening on weekends.")
        case .lunchBreak: String(localized: "\(share) of your listening between noon and 2 pm.")
        case .afterWork: String(localized: "\(share) of your listening between 6 and 10 pm.")
        case .allRounder: String(localized: "Any time is podcast time.")
        }
    }

    var symbolName: String {
        switch type {
        case .commuter: "tram.fill"
        case .nightOwl: "moon.stars.fill"
        case .earlyBird: "sunrise.fill"
        case .weekender: "sofa.fill"
        case .lunchBreak: "fork.knife"
        case .afterWork: "sunset.fill"
        case .allRounder: "clock.fill"
        }
    }
}

extension Conversion {
    /// "That's 19 football matches, without stoppage time." (I2, I20).
    var sentence: String {
        switch unit {
        case .issOrbit: String(localized: "In that time, the ISS orbits the earth \(count) times.")
        case .footballMatch: String(localized: "That's \(count) football matches, without stoppage time.")
        case .movie: String(localized: "That's \(count) feature films. Popcorn not included.")
        case .marathonWorldRecord: String(localized: "Enough time to run \(count) marathons at world record pace.")
        case .trainHamburgMunich: String(localized: "\(count) train rides from Hamburg to Munich. Without delays.")
        case .workday: String(localized: "\(count) working days. Only nicer.")
        case .nightOfSleep: String(localized: "\(count) nights of sleep. Well, almost.")
        case .flightFrankfurtNewYork: String(localized: "\(count) flights from Frankfurt to New York.")
        case .weekend: String(localized: "\(count) whole weekends.")
        case .nap: String(localized: "Enough for \(count) naps.")
        case .pastaCooking: String(localized: "Enough to cook pasta \(count) times.")
        case .washingCycle: String(localized: "That's \(count) washing cycles.")
        }
    }
}

extension Holiday {
    var name: String {
        switch self {
        case .christmasEve: String(localized: "Christmas Eve")
        case .newYearsEve: String(localized: "New Year's Eve")
        case .newYearsDay: String(localized: "New Year's Day")
        }
    }
}

/// A wink for some iTunes genres (I8); the rest gets none.
enum GenreQuip {
    static func quip(for genre: String) -> String? {
        let genre = genre.lowercased()
        if genre.contains("history") { return String(localized: "You live a little in the past.") }
        if genre.contains("news") { return String(localized: "Always up to date.") }
        if genre.contains("comedy") { return String(localized: "Laughter is the best medicine.") }
        if genre.contains("science") { return String(localized: "Curious, aren't you?") }
        if genre.contains("technology") { return String(localized: "Beep boop.") }
        if genre.contains("true crime") { return String(localized: "Should we be worried?") }
        if genre.contains("sports") { return String(localized: "Always on the ball.") }
        return nil
    }
}
