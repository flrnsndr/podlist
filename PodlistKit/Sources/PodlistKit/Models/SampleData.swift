import Foundation
import SwiftData

/// Deterministic sample library for UI tests (`-uiTesting`) and previews.
public enum SampleData {
    public static let referenceDate = Date(timeIntervalSinceReferenceDate: 812_000_000)  // Sep 2026

    /// Listening log: see `insertListeningSessions` and `insertHistory`.
    /// Inbox (concept §4.10), arrived at `now`: the newest episode of each podcast is done
    /// (auto-added, so not shown, N74); "Lage der Nation 4" (podcast with playlists, not in them) and
    /// "Zeit Verbrechen 1" (podcast without a playlist) are open.
    public static func insert(into context: ModelContext, now: Date = Date()) throws {
        let podcasts = [
            ("Lage der Nation", ["news", "politics"]),
            ("Hotel Matze", ["entertainment"]),
            ("Methodisch inkorrekt", ["knowledge", "technology"]),
        ]
        let playlists = try context.fetch(FetchDescriptor<Playlist>())
        // UI tests download by hand only; auto-download (on by default, N89) would load everything.
        for playlist in playlists { playlist.autoDownload = false }
        let playlistByKey = Dictionary(
            playlists.compactMap { p in p.systemKey.map { ($0, p) } }, uniquingKeysWith: { first, _ in first })

        for (index, (title, keys)) in podcasts.enumerated() {
            let slug = title.lowercased().replacingOccurrences(of: " ", with: "-")
            let podcast = Podcast(
                feedURL: URL(string: "https://example.com/\(slug)/feed.xml")!,
                title: title, subscribedAt: referenceDate)
            context.insert(podcast)
            for number in 1...3 {
                let episode = Episode(
                    guid: "\(slug)-\(number)", title: "\(title) \(number)",
                    publishedAt: referenceDate.addingTimeInterval(Double(index * 10 + number) * 86_400),
                    audioURL: URL(string: "https://example.com/\(slug)/\(number).mp3")!)
                episode.duration = 3_600
                episode.podcast = podcast
                insertChapters(into: episode, slug: slug, number: number)
            }
            for key in keys {
                guard let playlist = playlistByKey[key] else { continue }
                context.insert(PlaylistAssignment(podcast: podcast, playlist: playlist, autoAdd: .bottom, createdAt: referenceDate))
                for (position, episode) in (podcast.episodes ?? []).sorted(by: { $0.publishedAt < $1.publishedAt }).enumerated() {
                    context.insert(PlaylistEntry(
                        playlist: playlist, episode: episode, position: Double(position),
                        addedAt: referenceDate, origin: .automatic))
                }
            }
            if let newest = (podcast.episodes ?? []).max(by: { $0.publishedAt < $1.publishedAt }) {
                newest.inboxAddedAt = now
                newest.inboxState = .done
            }
            if index == 0 {
                insertInboxEpisode("Lage der Nation 4", slug: slug, of: podcast, publishedAt: referenceDate.addingTimeInterval(4 * 86_400), now: now, into: context)
            }
        }
        let unsorted = Podcast(feedURL: URL(string: "https://example.com/zeit-verbrechen/feed.xml")!, title: "Zeit Verbrechen", subscribedAt: referenceDate)
        context.insert(unsorted)
        insertInboxEpisode("Zeit Verbrechen 1", slug: "zeit-verbrechen", of: unsorted, publishedAt: referenceDate.addingTimeInterval(2 * 86_400), now: now, into: context)
        try context.save()
        try insertListeningSessions(into: context, now: now)
        try insertHistory(into: context, now: now)
    }

    /// Listening history (concept §4.12) on real sample episodes, besides the log of made-up
    /// ones: "Methodisch inkorrekt 1" started today and not finished, with a short
    /// description; "Lage der Nation 1" yesterday; "Hotel Matze 1" a year ago.
    private static func insertHistory(into context: ModelContext, now: Date, calendar: Calendar = .current) throws {
        let episodes = try context.fetch(FetchDescriptor<Episode>())
        func episode(_ title: String) -> Episode? { episodes.first { $0.title == title } }
        func session(_ title: String, at start: Date, from: TimeInterval, to: TimeInterval) {
            guard let episode = episode(title), start < now else { return }
            let session = ListeningSession(episodeUUID: episode.uuid, startedAt: start)
            session.endedAt = min(now, start.addingTimeInterval(to - from))
            session.listenedSeconds = to - from
            session.contentSeconds = to - from
            session.startPosition = from
            session.endPosition = to
            session.endReason = .paused
            session.podcastUUID = episode.podcast?.uuid
            session.playlistUUID = episode.playlistEntries?.first?.playlist?.uuid
            session.episodeTitle = episode.title
            session.podcastTitle = episode.podcast?.title ?? ""
            session.episodePublishedAt = episode.publishedAt
            session.episodeDuration = episode.duration
            context.insert(session)
        }
        if let started = episode("Methodisch inkorrekt 1") {
            started.subtitle = "Warum der Himmel blau ist"
            started.playbackPosition = 1_200
        }
        session("Methodisch inkorrekt 1", at: now.addingTimeInterval(-1_500), from: 0, to: 1_200)
        session("Lage der Nation 1", at: calendar.date(byAdding: .day, value: -1, to: now)!, from: 0, to: 600)
        session("Hotel Matze 1", at: calendar.date(byAdding: .year, value: -1, to: now)!, from: 0, to: 1_800)
        try context.save()
    }

    private static func insertInboxEpisode(
        _ title: String, slug: String, of podcast: Podcast, publishedAt: Date, now: Date, into context: ModelContext
    ) {
        let episode = Episode(
            guid: "\(slug)-inbox", title: title, publishedAt: publishedAt,
            audioURL: URL(string: "https://example.com/\(slug)/inbox.mp3")!)
        episode.duration = 3_600
        episode.podcast = podcast
        episode.inboxAddedAt = now
        episode.inboxState = .open
    }

    /// Lage der Nation 1 has Podlove chapters, Lage der Nation 2 timestamps in its show notes.
    private static func insertChapters(into episode: Episode, slug: String, number: Int) {
        guard slug == "lage-der-nation" else { return }
        switch number {
        case 1:
            episode.chapters = ChapterSelection.normalized([
                Chapter(start: 0, title: "Intro"),
                Chapter(start: 300, title: "Thema eins", linkURL: URL(string: "https://example.com/thema-eins")),
                Chapter(start: 1_800, title: "Thema zwei"),
            ], duration: episode.duration)
            episode.chaptersSource = .podlove
        case 2:
            episode.showNotes = "<p>Die Themen:</p><p>00:00 Begrüßung<br>12:30 Wahlrecht<br>41:05 Klimageld</p>"
        default:
            break
        }
    }
}
