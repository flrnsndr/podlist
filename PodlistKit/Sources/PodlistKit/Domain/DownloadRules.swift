import Foundation

/// An entry of a playlist with auto-download, in playlist order.
public struct AutoDownloadEntry: Hashable, Sendable {
    public var episode: EpisodeID
    public var isPlayed: Bool
    public var state: DownloadState

    public init(episode: EpisodeID, isPlayed: Bool, state: DownloadState) {
        self.episode = episode
        self.isPlayed = isPlayed
        self.state = state
    }
}

/// A downloaded episode for the storage overview.
public struct DownloadedEpisode: Hashable, Sendable {
    public var episode: EpisodeID
    public var podcast: PodcastID
    public var podcastTitle: String
    public var bytes: Int64
    public var isPlayed: Bool

    public init(episode: EpisodeID, podcast: PodcastID, podcastTitle: String, bytes: Int64, isPlayed: Bool) {
        self.episode = episode
        self.podcast = podcast
        self.podcastTitle = podcastTitle
        self.bytes = bytes
        self.isPlayed = isPlayed
    }
}

/// The downloads of one podcast.
public struct PodcastStorage: Hashable, Sendable {
    public var podcast: PodcastID
    public var title: String
    public var bytes: Int64
    public var episodeCount: Int
    /// How many of them are played, so it shows where clearing up pays off.
    public var playedCount: Int

    public init(podcast: PodcastID, title: String, bytes: Int64, episodeCount: Int, playedCount: Int = 0) {
        self.podcast = podcast
        self.title = title
        self.bytes = bytes
        self.episodeCount = episodeCount
        self.playedCount = playedCount
    }
}

/// What the storage screen shows (concept §4.7).
public struct StorageSummary: Hashable, Sendable {
    public var totalBytes: Int64
    public var playedBytes: Int64
    public var playedCount: Int
    /// Largest first.
    public var podcasts: [PodcastStorage]

    /// The part of the bar that "Gespielte löschen" keeps.
    public var unplayedBytes: Int64 { totalBytes - playedBytes }
}

/// How the "Downloads" section on the storage screen is sorted; the first case is the default.
public enum PodcastStorageSort: String, CaseIterable, Hashable, Sendable {
    /// Largest first.
    case size
    /// Alphabetical.
    case name
}

/// Download rules (concept §4.7).
public enum DownloadRules {
    /// N33: below this many free bytes automatic downloads stop.
    public static let lowStorageThreshold: Int64 = 1_000_000_000

    /// N33. An unknown capacity does not count as low.
    public static func isLowOnStorage(availableCapacity: Int64?) -> Bool {
        guard let availableCapacity else { return false }
        return availableCapacity < lowStorageThreshold
    }

    /// The episodes the automatic download starts, in order (N31): every unplayed episode
    /// of the auto-download playlists that is not loaded, waiting or loading. Failed ones
    /// wait for "Erneut versuchen" (A38). Nothing while paused (A39) or low on storage (N33).
    public static func automaticDownloads(
        _ entries: [AutoDownloadEntry], availableCapacity: Int64?, isPaused: Bool
    ) -> [EpisodeID] {
        guard !isPaused, !isLowOnStorage(availableCapacity: availableCapacity) else { return [] }
        var seen: Set<EpisodeID> = []
        return entries
            .filter { !$0.isPlayed && $0.state == .none }
            .map(\.episode)
            .filter { seen.insert($0).inserted }
    }

    /// N32, A37: a played episode's download (or the attempt) goes once it has left the
    /// player, in every playlist, if the setting is on.
    public static func shouldDeletePlayedDownload(
        isPlayed: Bool, state: DownloadState, isNowPlaying: Bool, deletesPlayed: Bool
    ) -> Bool {
        deletesPlayed && isPlayed && !isNowPlaying && state != .none
    }

    public static func summary(_ downloads: [DownloadedEpisode]) -> StorageSummary {
        let played = downloads.filter(\.isPlayed)
        let podcasts: [PodcastStorage] = Dictionary(grouping: downloads, by: \.podcast).map { id, episodes in
            PodcastStorage(podcast: id, title: episodes[0].podcastTitle, bytes: totalBytes(of: episodes),
                           episodeCount: episodes.count, playedCount: episodes.count(where: \.isPlayed))
        }
        return StorageSummary(
            totalBytes: totalBytes(of: downloads),
            playedBytes: totalBytes(of: played),
            playedCount: played.count,
            podcasts: sorted(podcasts, by: .size))
    }

    /// Ties fall back to the other key, so the list does not jump.
    public static func sorted(_ podcasts: [PodcastStorage], by sort: PodcastStorageSort) -> [PodcastStorage] {
        switch sort {
        case .size:
            podcasts.sorted(by: isLarger)
        case .name:
            podcasts.sorted { a, b in
                let order = a.title.localizedStandardCompare(b.title)
                return order == .orderedSame ? a.bytes > b.bytes : order == .orderedAscending
            }
        }
    }

    private static func totalBytes(of downloads: [DownloadedEpisode]) -> Int64 {
        downloads.reduce(0) { $0 + $1.bytes }
    }

    /// Largest first; the same size alphabetically, so the list does not jump.
    private static func isLarger(_ a: PodcastStorage, _ b: PodcastStorage) -> Bool {
        if a.bytes != b.bytes { return a.bytes > b.bytes }
        return a.title.localizedStandardCompare(b.title) == .orderedAscending
    }
}
