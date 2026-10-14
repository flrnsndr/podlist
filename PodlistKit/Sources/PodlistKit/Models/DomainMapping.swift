import Foundation
import SwiftData

// Translation from `@Model` objects to the domain's value types (concept §6.2).

extension Episode {
    private static let noPodcast = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    public var episodeID: EpisodeID { EpisodeID(uuid) }

    public var info: EpisodeInfo {
        EpisodeInfo(
            id: episodeID, podcastID: PodcastID(podcast?.uuid ?? Self.noPodcast),
            podcastTitle: podcast?.title ?? "", title: title, publishedAt: publishedAt,
            duration: duration, playbackPosition: playbackPosition, playedAt: playedAt)
    }

    /// The episode is the one in the player (`QueueItem.isNowPlaying`).
    var isNowPlaying: Bool {
        (queueItems ?? []).contains { $0.isNowPlaying }
    }

    /// The inbox's view of the episode; `nil` if it was never in the inbox.
    public var inboxValue: InboxEpisode? {
        guard let inboxAddedAt else { return nil }
        return InboxEpisode(
            id: episodeID, publishedAt: publishedAt, addedAt: inboxAddedAt, state: inboxState,
            podcastPlaylists: Set((podcast?.assignments ?? []).compactMap { $0.playlist?.playlistID }),
            podcastIsSubscribed: podcast?.isSubscribed ?? false,
            podcastIsHidden: podcast?.isHiddenFromAll ?? false)
    }

    var inboxCandidate: InboxCandidate {
        InboxCandidate(
            id: episodeID, publishedAt: publishedAt, wasInInbox: inboxAddedAt != nil,
            isInPlaylist: !(playlistEntries ?? []).isEmpty)
    }

    /// The episode was dealt with: it landed in a playlist, went to Up Next, started playing
    /// or was marked played (A50, N44, N46, N49). Open in the inbox → done. Does not save.
    func inboxHandled() {
        guard inboxAddedAt != nil else { return }
        let state = InboxRules.state(inboxState, after: .handled)
        if state != inboxState { inboxState = state }
    }

    /// Auto-add put the episode into playlists: done only if it is in every playlist of its
    /// podcast now; partial auto-add leaves it open (N75, A68). Does not save.
    func inboxAutoAdded() {
        guard inboxAddedAt != nil, inboxState == .open else { return }
        let inPlaylists = Set((playlistEntries ?? []).filter { !$0.isDeleted }.compactMap { $0.playlist?.playlistID })
        let assigned = Set((podcast?.assignments ?? []).filter { !$0.isDeleted }.compactMap { $0.playlist?.playlistID })
        if InboxRules.isSortedByAutoAdd(inPlaylists: inPlaylists, podcastPlaylists: assigned) { inboxHandled() }
    }
}

extension Podcast {
    /// All of its playlists are hidden: left out of "Alle" in the library and the inbox (N65).
    public var isHiddenFromAll: Bool {
        let playlists = (assignments ?? []).compactMap(\.playlist)
        return HiddenPlaylists.hidesPodcast(
            in: Set(playlists.map(\.playlistID)), hidden: Set(playlists.filter(\.isHidden).map(\.playlistID)))
    }
}

extension Array where Element == Playlist {
    /// The playlists for display, split by `HiddenPlaylists.split` (N66).
    public func splitByHidden(pinned: Set<UUID> = []) -> (shown: [Playlist], behindMore: [Playlist]) {
        let byID = Dictionary(map { ($0.playlistID, $0) }, uniquingKeysWith: { first, _ in first })
        let split = HiddenPlaylists.split(map { ($0.playlistID, $0.isHidden) }, pinned: Set(pinned.map(PlaylistID.init)))
        return (split.shown.compactMap { byID[$0] }, split.behindMore.compactMap { byID[$0] })
    }
}

extension PlaylistEntry {
    /// `nil` while the entry has no episode (it is being deleted).
    public var info: PlaylistEntryInfo? {
        episode.map { PlaylistEntryInfo(episode: $0.info, position: position, addedAt: addedAt) }
    }
}

extension Playlist {
    public var playlistID: PlaylistID { PlaylistID(uuid) }

    /// Entries in the playlist's display sort (concept §4.2); for `podcast` the sections
    /// concatenated, which is also the order the queue plays.
    public var sortedEntries: [PlaylistEntry] {
        let entries = (entries ?? []).filter { $0.episode != nil }
        let byEpisode = Dictionary(entries.map { ($0.episode!.episodeID, $0) }, uniquingKeysWith: { first, _ in first })
        return PlaylistSorting.sorted(entries.compactMap(\.info), by: sort, ascending: sortAscending)
            .compactMap { byEpisode[$0.episode.id] }
    }

    /// The playlist as the queue sees it (cursor rules, concept §4.4). `playlists`: all
    /// playlists, which "Alles" mirrors.
    func queuePlaylist(among playlists: [Playlist]) -> QueuePlaylist {
        let content = content(among: playlists)
        return QueuePlaylist(
            id: playlistID, playedPolicy: playedPolicy,
            episodes: content.sorted(by: sort, ascending: sortAscending).map(\.episodeID),
            resumeEpisode: resumeEpisode?.episodeID)
    }
}

// MARK: - "Alles" (concept §4.1, N70–N73)

extension Playlist {
    /// The `systemKey` of the playlist "Alles".
    public static let everythingKey = "everything"

    /// The playlist "Alles": mirrors the other playlists, is no tag.
    public var isEverything: Bool { systemKey == Self.everythingKey }

    /// What the playlist holds: its own entries, or for "Alles" those of the chosen
    /// `playlists` (N71). `playlists` is only read for "Alles".
    public func content(among playlists: [Playlist]) -> PlaylistContent {
        guard isEverything else {
            let entries = (entries ?? []).filter { $0.episode != nil }
            return PlaylistContent(entries: entries.compactMap(\.info), episodes: entries.compactMap(\.episode))
        }
        let tags = playlists.tags
        var sources: [Everything.Source] = []
        var episodes: [Episode] = []
        var excludedPodcasts: Set<PodcastID> = []
        for playlist in tags {
            for entry in playlist.entries ?? [] {
                guard let episode = entry.episode, let info = entry.info else { continue }
                sources.append(Everything.Source(entry: info, playlist: playlist.playlistID))
                episodes.append(episode)
                if episode.podcast?.isExcludedFromEverything == true { excludedPodcasts.insert(info.episode.podcastID) }
            }
        }
        let entries = Everything.entries(
            sources, excludedPlaylists: Set(tags.filter(\.isExcludedFromEverything).map(\.playlistID)),
            excludedPodcasts: excludedPodcasts)
        return PlaylistContent(entries: entries, episodes: episodes)
    }

    /// Its episodes as the playlist screen lists them, in its sort. "Alles" with "remove"
    /// shows only unplayed episodes (N70); other playlists show all of their entries.
    public func shownEpisodes(among playlists: [Playlist]) -> [Episode] {
        var content = content(among: playlists)
        if isEverything { content.entries = Everything.shown(content.entries) }
        return content.sorted(by: sort, ascending: sortAscending)
    }
}

/// A playlist's content as values for sorting, with the episodes behind them (concept §4.2).
public struct PlaylistContent {
    public var entries: [PlaylistEntryInfo]
    private let episodes: [EpisodeID: Episode]

    init(entries: [PlaylistEntryInfo], episodes: [Episode]) {
        self.entries = entries
        self.episodes = Dictionary(episodes.map { ($0.episodeID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func episode(_ id: EpisodeID) -> Episode? { episodes[id] }

    /// The episodes in the given sort (for `podcast` the sections concatenated).
    public func sorted(by sort: PlaylistSort, ascending: Bool) -> [Episode] {
        PlaylistSorting.sorted(entries, by: sort, ascending: ascending).compactMap { episodes[$0.episode.id] }
    }
}

extension Array where Element == Playlist {
    /// The playlists as tags (filters, assigning, "Zu Playlist …", suggestions, statistics):
    /// all but "Alles".
    public var tags: [Playlist] { filter { !$0.isEverything } }

    /// The playlist "Alles", if it exists.
    public var everything: Playlist? { first(where: \.isEverything) }
}

extension Podcast {
    /// As the notification settings see it (N87): its playlists without "Alles".
    public var notificationPodcast: NotificationPodcast {
        NotificationPodcast(
            id: PodcastID(uuid), title: title, isOn: notificationsEnabled,
            playlists: Set((assignments ?? []).compactMap(\.playlist).tags.map(\.playlistID)))
    }
}

extension Episode {
    /// The episode is in "Alles", also once it has left the playlists in `leaving` (N71).
    func isInEverything(leaving: Set<PlaylistID> = []) -> Bool {
        let playlists = (playlistEntries ?? []).compactMap(\.playlist).filter { !$0.isEverything }
        return Everything.includes(
            inPlaylists: Set(playlists.map(\.playlistID)).subtracting(leaving),
            excludedPlaylists: Set(playlists.filter(\.isExcludedFromEverything).map(\.playlistID)),
            podcastIsExcluded: podcast?.isExcludedFromEverything ?? false)
    }
}
