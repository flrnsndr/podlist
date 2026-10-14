import Foundation
import SwiftData

extension SampleData {
    /// A made-up library for the website screenshots (`-screenshots`), in German or English:
    /// podcasts with artwork, playlists with a place to continue from, a queue with playlist
    /// blocks, open episodes in the inbox and months of listening. `artwork` returns the cover
    /// for a podcast's slug (the app renders them, tests pass any URL).
    public static func insertScreenshots(
        into context: ModelContext, german: Bool, artwork: (String) -> URL?, now: Date = Date()
    ) throws {
        let defaults = try context.fetch(FetchDescriptor<Playlist>())
        var playlists = Dictionary(
            defaults.compactMap { p in p.systemKey.map { ($0, p) } }, uniquingKeysWith: { first, _ in first })
        for playlist in defaults { playlist.autoDownload = false }
        let business = Playlist(
            customName: german ? "Wirtschaft" : "Business", colorKey: "mint", symbolName: "chart.line.uptrend.xyaxis",
            displayOrder: (defaults.map(\.displayOrder).max() ?? 0) + 1)
        context.insert(business)
        playlists["business"] = business
        // News newest first; the others in the order the episodes came out.
        playlists["news"]?.sort = .published
        playlists["news"]?.sortAscending = false

        var episodesBySlug: [String: [Episode]] = [:]
        for show in screenshotShows {
            let podcast = Podcast(
                feedURL: URL(string: "https://example.com/\(show.slug)/feed.xml")!,
                title: german ? show.title.de : show.title.en, subscribedAt: now.addingTimeInterval(-400 * 86_400))
            podcast.author = german ? show.author.de : show.author.en
            podcast.artworkURL = artwork(show.slug)
            context.insert(podcast)
            for (key, rule) in show.playlists {
                guard let playlist = playlists[key] else { continue }
                context.insert(PlaylistAssignment(podcast: podcast, playlist: playlist, autoAdd: rule, createdAt: podcast.subscribedAt))
            }
            var episodes: [Episode] = []
            for (number, spec) in show.episodes.enumerated() {
                let episode = Episode(
                    guid: "\(show.slug)-\(number)", title: german ? spec.title.de : spec.title.en,
                    publishedAt: now.addingTimeInterval(-spec.daysAgo * 86_400 - 3 * 3_600),
                    audioURL: URL(string: "https://example.com/\(show.slug)/\(number).mp3")!)
                episode.duration = spec.minutes * 60
                episode.playbackPosition = spec.listenedMinutes * 60
                episode.podcast = podcast
                if spec.isInInbox {
                    episode.inboxAddedAt = episode.publishedAt
                    episode.inboxState = .open
                } else {
                    let keys = spec.playlists ?? show.playlists.filter { $0.1 != .off }.map(\.0)
                    for key in keys {
                        guard let playlist = playlists[key] else { continue }
                        let position = Double(playlist.entries?.count ?? 0)
                        context.insert(PlaylistEntry(
                            playlist: playlist, episode: episode, position: position, addedAt: episode.publishedAt,
                            origin: spec.playlists == nil ? .automatic : .manual))
                    }
                }
                episodes.append(episode)
            }
            episodesBySlug[show.slug] = episodes
        }

        // Queue: the morning news from the News playlist, then one recommended episode, then
        // Sports and Technology; each playlist knows where it continues.
        let morning = episodesBySlug["morning"]![0]
        playlists["news"]?.resumeEpisode = morning
        playlists["sports"]?.resumeEpisode = episodesBySlug["whistle"]![1]
        playlists["technology"]?.resumeEpisode = episodesBySlug["circuit"]![0]
        playlists["politics"]?.resumeEpisode = episodesBySlug["interjection"]![1]
        playlists["knowledge"]?.resumeEpisode = episodesBySlug["long-road"]![1]
        context.insert(QueueItem(nowPlaying: morning, playlist: playlists["news"]))
        context.insert(QueueItem(position: 0, episode: episodesBySlug["headwind"]![1]))
        if let sports = playlists["sports"] { context.insert(QueueItem(position: 1, playlist: sports)) }
        if let technology = playlists["technology"] { context.insert(QueueItem(position: 2, playlist: technology)) }

        try context.save()
        try insertListeningSessions(into: context, now: now, cast: ListeningCast(
            daily: german ? "Morgenlage" : "Morning Brief", riser: german ? "Am Küchentisch" : "Kitchen Table",
            science: german ? "Stromkreis" : "Circuit", bedtime: german ? "Sternwarte" : "Observatory",
            weekend: german ? "Der lange Weg" : "The Long Road", cooled: german ? "Abpfiff" : "Final Whistle",
            comedy: german ? "Gegenwind" : "Headwind"))
    }

    private struct Text {
        var de: String
        var en: String
        init(_ de: String, _ en: String) {
            self.de = de
            self.en = en
        }
    }

    private struct ScreenshotEpisode {
        var title: Text
        var minutes: Double
        var daysAgo: Double
        var listenedMinutes: Double = 0
        /// nil: every playlist the podcast adds to automatically.
        var playlists: [String]?
        var isInInbox = false
    }

    private struct ScreenshotShow {
        var slug: String
        var title: Text
        var author: Text
        var playlists: [(String, AutoAddRule)]
        var episodes: [ScreenshotEpisode]
    }

    /// Newest episode first.
    private static let screenshotShows: [ScreenshotShow] = [
        ScreenshotShow(
            slug: "morning", title: Text("Morgenlage", "Morning Brief"), author: Text("Redaktion Morgenlage", "Morning Brief Desk"),
            playlists: [("news", .bottom)],
            episodes: [
                ScreenshotEpisode(title: Text("Streik bei der Bahn, Tag zwei", "Rail Strike, Day Two"), minutes: 22, daysAgo: 0, listenedMinutes: 9),
                ScreenshotEpisode(title: Text("Neue Zahlen zur Inflation", "New Inflation Figures"), minutes: 19, daysAgo: 1),
                ScreenshotEpisode(title: Text("Gipfel in Brüssel", "Summit in Brussels"), minutes: 24, daysAgo: 2),
                ScreenshotEpisode(title: Text("Was der Wahlausgang bedeutet", "What the Election Result Means"), minutes: 21, daysAgo: 3),
            ]),
        ScreenshotShow(
            slug: "floor-notes", title: Text("Plenarnotizen", "Floor Notes"), author: Text("Plenarnotizen", "Floor Notes"),
            playlists: [("politics", .off), ("business", .off)],
            episodes: [
                ScreenshotEpisode(title: Text("Folge 214: Der Haushalt", "Episode 214: The Budget"), minutes: 48, daysAgo: 0, isInInbox: true),
                ScreenshotEpisode(title: Text("Folge 213: Wahlrecht erklärt", "Episode 213: Electoral Law Explained"), minutes: 52, daysAgo: 7, listenedMinutes: 31, playlists: ["politics"]),
                ScreenshotEpisode(title: Text("Folge 212: Wer zahlt die Rente?", "Episode 212: Who Pays for Pensions?"), minutes: 45, daysAgo: 14, playlists: ["politics", "business"]),
            ]),
        ScreenshotShow(
            slug: "interjection", title: Text("Zwischenruf", "Interjection"), author: Text("Zwischenruf", "Interjection"),
            playlists: [("politics", .bottom), ("news", .off)],
            episodes: [
                ScreenshotEpisode(title: Text("Europa nach der Wahl", "Europe After the Vote"), minutes: 38, daysAgo: 2),
                ScreenshotEpisode(title: Text("Die Woche im Bundestag", "This Week in Parliament"), minutes: 41, daysAgo: 5, listenedMinutes: 12),
            ]),
        ScreenshotShow(
            slug: "market", title: Text("Marktbericht", "Market Report"), author: Text("Marktbericht", "Market Report"),
            playlists: [("business", .bottom)],
            episodes: [
                ScreenshotEpisode(title: Text("Was Zinsen bewirken", "What Interest Rates Do"), minutes: 33, daysAgo: 3),
                ScreenshotEpisode(title: Text("Lieferketten", "Supply Chains"), minutes: 29, daysAgo: 10),
            ]),
        ScreenshotShow(
            slug: "whistle", title: Text("Abpfiff", "Final Whistle"), author: Text("Abpfiff", "Final Whistle"),
            playlists: [("sports", .bottom)],
            episodes: [
                ScreenshotEpisode(title: Text("Der 7. Spieltag in 30 Minuten", "Matchday 7 in 30 Minutes"), minutes: 31, daysAgo: 1),
                ScreenshotEpisode(title: Text("Taktiktafel: Pressing", "Tactics Board: Pressing"), minutes: 44, daysAgo: 4, listenedMinutes: 20),
                ScreenshotEpisode(title: Text("Transfergerüchte", "Transfer Rumours"), minutes: 27, daysAgo: 6),
            ]),
        ScreenshotShow(
            slug: "circuit", title: Text("Stromkreis", "Circuit"), author: Text("Stromkreis", "Circuit"),
            playlists: [("technology", .bottom)],
            episodes: [
                ScreenshotEpisode(title: Text("Akkus, die nicht altern", "Batteries That Don’t Age"), minutes: 56, daysAgo: 2),
                ScreenshotEpisode(title: Text("Das Ende der Passwörter", "The End of Passwords"), minutes: 63, daysAgo: 9),
                ScreenshotEpisode(title: Text("Chips aus Europa", "Chips Made in Europe"), minutes: 49, daysAgo: 16),
            ]),
        ScreenshotShow(
            slug: "long-road", title: Text("Der lange Weg", "The Long Road"), author: Text("Der lange Weg", "The Long Road"),
            playlists: [("knowledge", .off)],
            episodes: [
                ScreenshotEpisode(title: Text("Die Seidenstraße, Teil 4: Venedig", "The Silk Road, Part 4: Venice"), minutes: 58, daysAgo: 1, isInInbox: true),
                ScreenshotEpisode(title: Text("Die Seidenstraße, Teil 3: Über das Gebirge", "The Silk Road, Part 3: Over the Mountains"), minutes: 61, daysAgo: 8, playlists: ["knowledge"]),
                ScreenshotEpisode(title: Text("Die Seidenstraße, Teil 2: Samarkand", "The Silk Road, Part 2: Samarkand"), minutes: 55, daysAgo: 15, listenedMinutes: 40, playlists: ["knowledge"]),
            ]),
        ScreenshotShow(
            slug: "observatory", title: Text("Sternwarte", "Observatory"), author: Text("Sternwarte", "Observatory"),
            playlists: [("knowledge", .bottom)],
            episodes: [
                ScreenshotEpisode(title: Text("Wie schwer ist ein Schwarzes Loch?", "How Heavy Is a Black Hole?"), minutes: 18, daysAgo: 4),
                ScreenshotEpisode(title: Text("Warum der Mond sich entfernt", "Why the Moon Is Drifting Away"), minutes: 16, daysAgo: 11),
            ]),
        ScreenshotShow(
            slug: "kitchen", title: Text("Am Küchentisch", "Kitchen Table"), author: Text("Am Küchentisch", "Kitchen Table"),
            playlists: [("entertainment", .bottom)],
            episodes: [
                ScreenshotEpisode(title: Text("Urlaub mit Hindernissen", "A Holiday Gone Sideways"), minutes: 74, daysAgo: 2),
                ScreenshotEpisode(title: Text("Der Umzug", "The Move"), minutes: 68, daysAgo: 9),
            ]),
        ScreenshotShow(
            slug: "headwind", title: Text("Gegenwind", "Headwind"), author: Text("Gegenwind", "Headwind"),
            playlists: [("entertainment", .off)],
            episodes: [
                ScreenshotEpisode(title: Text("Drei Stunden mit einer Bergführerin", "Three Hours with a Mountain Guide"), minutes: 184, daysAgo: 0, isInInbox: true),
                ScreenshotEpisode(title: Text("Im Gespräch mit einem Notarzt", "In Conversation with an ER Doctor"), minutes: 162, daysAgo: 12, playlists: ["entertainment"]),
            ]),
        ScreenshotShow(
            slug: "odds-and-ends", title: Text("Fundstücke", "Odds & Ends"), author: Text("Fundstücke", "Odds & Ends"),
            playlists: [],
            episodes: [
                ScreenshotEpisode(title: Text("Die Geschichte der Büroklammer", "The History of the Paper Clip"), minutes: 26, daysAgo: 1, isInInbox: true),
            ]),
    ]
}
