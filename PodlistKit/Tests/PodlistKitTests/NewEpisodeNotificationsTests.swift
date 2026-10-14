import Foundation
import Testing
@testable import PodlistKit

/// Which new episodes get a notification (N35, A45) and whether it offers "Zu Playlists
/// hinzufügen" (N34).
struct NewEpisodeNotificationsTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 812_000_000)
    private static let day: TimeInterval = 24 * 3600

    private func candidate(
        _ id: EpisodeID = EpisodeID(), podcast: PodcastID, daysAgo: Double = 0, enabled: Bool = true
    ) -> NewEpisodeCandidate {
        NewEpisodeCandidate(
            episode: id, podcast: podcast, publishedAt: Self.now.addingTimeInterval(-daysAgo * Self.day),
            notificationsEnabled: enabled)
    }

    @Test func onlyPodcastsWithNotificationsEnabled() {
        let (on, off) = (PodcastID(), PodcastID())
        let (a, b) = (EpisodeID(), EpisodeID())
        let ids = NewEpisodeNotifications.episodesToNotify(
            [candidate(a, podcast: on), candidate(b, podcast: off, enabled: false)], now: Self.now)
        #expect(ids == [a])
    }

    /// A45: older episodes are archive episodes the feed changed (e.g. new GUIDs), not news.
    @Test(arguments: [(6.9, true), (7.0, true), (7.1, false), (-1.0, true)])
    func onlyEpisodesOfTheLastSevenDays(daysAgo: Double, notifies: Bool) {
        let id = EpisodeID()
        let ids = NewEpisodeNotifications.episodesToNotify([candidate(id, podcast: PodcastID(), daysAgo: daysAgo)], now: Self.now)
        #expect(ids == (notifies ? [id] : []))
    }

    /// A45: at most the three newest per podcast, oldest of them first (the last posted shows
    /// on top); podcasts in input order.
    @Test func atMostTheThreeNewestPerPodcast() {
        let (p, q) = (PodcastID(), PodcastID())
        let e = (0..<5).map { _ in EpisodeID() }
        let other = EpisodeID()
        let candidates = [
            candidate(e[0], podcast: p, daysAgo: 4), candidate(e[1], podcast: p, daysAgo: 0),
            candidate(other, podcast: q, daysAgo: 1),
            candidate(e[2], podcast: p, daysAgo: 3), candidate(e[3], podcast: p, daysAgo: 1),
            candidate(e[4], podcast: p, daysAgo: 2),
        ]
        let ids = NewEpisodeNotifications.episodesToNotify(candidates, now: Self.now)
        #expect(ids == [e[4], e[3], e[1], other])
    }

    /// N34: "Zu Playlists hinzufügen" adds to the assigned playlists that miss the episode.
    @Test func playlistsToAddToAreTheAssignedOnesWithoutTheEpisode() {
        let (a, b, c) = (PlaylistID(), PlaylistID(), PlaylistID())
        #expect(NewEpisodeNotifications.playlistsToAdd(assigned: [a, b, c], containing: [b]) == [a, c])
        #expect(NewEpisodeNotifications.playlistsToAdd(assigned: [a], containing: [a, c]).isEmpty)
        #expect(NewEpisodeNotifications.playlistsToAdd(assigned: [], containing: []).isEmpty)
    }
}
