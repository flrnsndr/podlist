import Foundation

/// The playlist "Alles" (concept §4.1, N70–N73): every episode that is in at least one other
/// playlist, once, without the playlists and podcasts left out. It stores no entries of its
/// own; services compute its content from the other playlists' entries, so it never changes
/// another playlist (N73).
public enum Everything {
    /// One entry of another playlist, as "Alles" sees it.
    public struct Source: Hashable, Sendable {
        public var entry: PlaylistEntryInfo
        public var playlist: PlaylistID

        public init(entry: PlaylistEntryInfo, playlist: PlaylistID) {
            self.entry = entry
            self.playlist = playlist
        }
    }

    /// The one sort of "Alles" (N97): "Hinzugefügt, neueste zuerst", for showing and playing.
    /// It has no positions of its own, so there is no manual sort and nothing to choose.
    public static let sort = PlaylistSort.added
    public static let sortAscending = false

    /// An episode in these playlists belongs to "Alles" while one of them is still chosen
    /// (sichtbar gewinnt, N71); a podcast left out is always out.
    public static func includes(inPlaylists playlists: Set<PlaylistID>, excludedPlaylists: Set<PlaylistID>, podcastIsExcluded: Bool) -> Bool {
        !podcastIsExcluded && !playlists.isSubset(of: excludedPlaylists)
    }

    /// The content of "Alles": one entry per episode in the order of first appearance,
    /// unsorted (sorting is a view, §4.2). "Hinzugefügt" is the latest of its entries in a
    /// chosen playlist (N97); the position is 0 for all.
    public static func entries(
        _ sources: [Source], excludedPlaylists: Set<PlaylistID>, excludedPodcasts: Set<PodcastID>
    ) -> [PlaylistEntryInfo] {
        var order: [EpisodeID] = []
        var byEpisode: [EpisodeID: PlaylistEntryInfo] = [:]
        for source in sources where !excludedPlaylists.contains(source.playlist) {
            let episode = source.entry.episode
            guard !excludedPodcasts.contains(episode.podcastID) else { continue }
            if let existing = byEpisode[episode.id] {
                if source.entry.addedAt > existing.addedAt { byEpisode[episode.id]?.addedAt = source.entry.addedAt }
            } else {
                order.append(episode.id)
                byEpisode[episode.id] = PlaylistEntryInfo(episode: episode, position: 0, addedAt: source.entry.addedAt)
            }
        }
        return order.compactMap { byEpisode[$0] }
    }

    /// What "Alles" shows: only unplayed episodes, it always removes played ones (N99). The
    /// queue gets all `entries` and skips played ones itself (`QueueResolver`).
    public static func shown(_ entries: [PlaylistEntryInfo]) -> [PlaylistEntryInfo] {
        entries.filter { !$0.episode.isPlayed }
    }
}
