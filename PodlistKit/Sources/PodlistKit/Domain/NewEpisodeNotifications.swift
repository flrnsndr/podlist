import Foundation

/// A new episode found by a refresh, as the notification rules see it.
public struct NewEpisodeCandidate: Hashable, Sendable {
    public var episode: EpisodeID
    public var podcast: PodcastID
    public var publishedAt: Date
    public var notificationsEnabled: Bool

    public init(episode: EpisodeID, podcast: PodcastID, publishedAt: Date, notificationsEnabled: Bool) {
        self.episode = episode
        self.podcast = podcast
        self.publishedAt = publishedAt
        self.notificationsEnabled = notificationsEnabled
    }
}

/// Which new episodes get a notification (N35, A45) and what "Zu Playlists hinzufügen"
/// adds the episode to (N34).
public enum NewEpisodeNotifications {
    /// Older "new" episodes are archive episodes the feed changed, not news.
    public static let maxAge: TimeInterval = 7 * 24 * 3600
    public static let maxPerPodcast = 3

    /// The episodes to notify: podcasts with notifications on, published within `maxAge`,
    /// the newest `maxPerPodcast` per podcast. Podcasts in input order, each podcast's
    /// episodes oldest first: posted in this order, the newest ends up on top.
    public static func episodesToNotify(_ candidates: [NewEpisodeCandidate], now: Date) -> [EpisodeID] {
        let eligible = candidates.filter { $0.notificationsEnabled && now.timeIntervalSince($0.publishedAt) <= maxAge }
        var podcasts: [PodcastID] = []
        var byPodcast: [PodcastID: [NewEpisodeCandidate]] = [:]
        for candidate in eligible {
            if byPodcast[candidate.podcast] == nil { podcasts.append(candidate.podcast) }
            byPodcast[candidate.podcast, default: []].append(candidate)
        }
        return podcasts.flatMap { podcast in
            (byPodcast[podcast] ?? []).sorted { $0.publishedAt > $1.publishedAt }.prefix(maxPerPodcast).reversed().map(\.episode)
        }
    }

    /// The assigned playlists that do not contain the episode yet, in `assigned` order.
    /// Empty: the notification offers no "Zu Playlists hinzufügen".
    public static func playlistsToAdd(assigned: [PlaylistID], containing: Set<PlaylistID>) -> [PlaylistID] {
        assigned.filter { !containing.contains($0) }
    }
}
