import Foundation

/// Where an episode stands in the inbox (Eingang, concept §4.10). Stored as
/// `Episode.inboxStateRaw`; only meaningful while `Episode.inboxAddedAt` is set.
public enum InboxState: String, Sendable, Codable, CaseIterable {
    /// Waiting to be sorted into playlists.
    case open
    /// In a playlist, in Up Next, played or started (A50, N46, N49). Leaves the inbox (N74).
    case done
    /// "Aussortieren" (N77): out of the inbox, still in the podcast.
    case discarded
}

/// Why episodes were just inserted into the library (A49, N48).
public enum InboxArrival: Sendable {
    /// A feed refresh found them.
    case refresh
    /// Subscribing, also subscribing again.
    case subscribe
    /// The OPML import.
    case opmlImport
}

/// An episode the inbox might take in. For `.refresh` the candidates are the episodes the
/// refresh inserted; for `.subscribe` all of the podcast's episodes, new and kept (§4.9), in
/// feed order.
public struct InboxCandidate: Hashable, Sendable {
    public var id: EpisodeID
    public var publishedAt: Date
    /// It has an `inboxAddedAt` already: it never enters a second time.
    public var wasInInbox: Bool
    /// It is in a playlist already (e.g. kept after unsubscribing).
    public var isInPlaylist: Bool

    public init(id: EpisodeID, publishedAt: Date, wasInInbox: Bool, isInPlaylist: Bool = false) {
        self.id = id
        self.publishedAt = publishedAt
        self.wasInInbox = wasInInbox
        self.isInPlaylist = isInPlaylist
    }
}

/// An episode that is or was in the inbox.
public struct InboxEpisode: Hashable, Sendable {
    public var id: EpisodeID
    public var publishedAt: Date
    /// When it arrived in the inbox.
    public var addedAt: Date
    public var state: InboxState
    /// The playlists its podcast is assigned to (the podcast's "tags").
    public var podcastPlaylists: Set<PlaylistID>
    public var podcastIsSubscribed: Bool
    /// All of its podcast's playlists are hidden (`HiddenPlaylists`, N65): not under "Alle".
    public var podcastIsHidden: Bool

    public init(
        id: EpisodeID, publishedAt: Date, addedAt: Date, state: InboxState,
        podcastPlaylists: Set<PlaylistID>, podcastIsSubscribed: Bool, podcastIsHidden: Bool = false
    ) {
        self.id = id
        self.publishedAt = publishedAt
        self.addedAt = addedAt
        self.state = state
        self.podcastPlaylists = podcastPlaylists
        self.podcastIsSubscribed = podcastIsSubscribed
        self.podcastIsHidden = podcastIsHidden
    }
}

/// The filter chips of the library and the inbox (A56).
public enum PlaylistFilter: Hashable, Sendable {
    /// Everything except hidden podcasts (N65).
    case all
    /// Podcasts assigned to this playlist.
    case playlist(PlaylistID)
    /// "Ohne Playlist": podcasts without an assignment.
    case withoutPlaylist
}

/// What happened to an episode, as far as the inbox cares.
public enum InboxEvent: Hashable, Sendable {
    /// Landed in a playlist, went to Up Next, started playing or was marked played.
    case handled
    /// "Aussortieren" (N77).
    case discarded
}

/// The inbox rules (concept §4.10): which episodes enter, how long they stay, open → done,
/// what shows (open ones, and below them the ones just done), the filter, the number on the
/// tab. Pure logic on values; the clock is injected.
public enum InboxRules {
    /// A48: an episode stays this long, counted from its arrival in the inbox.
    public static let retention: TimeInterval = 14 * 24 * 3600

    /// The episodes among `candidates` that enter the inbox now (A49, N48): after a refresh
    /// the new ones of the last 14 days (by publication date, inclusive), when subscribing
    /// only the newest (the first one in feed order on equal dates), from the OPML import none.
    public static func entering(_ candidates: [InboxCandidate], arrival: InboxArrival, now: Date) -> [EpisodeID] {
        switch arrival {
        case .refresh:
            let oldest = now.addingTimeInterval(-retention)
            return candidates.filter { !$0.wasInInbox && $0.publishedAt >= oldest }.map(\.id)
        case .subscribe:
            let newest = candidates.reduce(nil as InboxCandidate?) { best, next in
                guard let best else { return next }
                return next.publishedAt > best.publishedAt ? next : best
            }
            guard let newest, !newest.wasInInbox else { return [] }
            return [newest.id]
        case .opmlImport:
            return []
        }
    }

    /// An entering episode that is in a playlist already (kept after unsubscribing, §4.9; the
    /// assignments are gone then, so it is sorted completely, N75) is done right away.
    public static func initialState(of candidate: InboxCandidate) -> InboxState {
        candidate.isInPlaylist ? .done : .open
    }

    /// N75, A68: after auto-add (or with an entry kept after unsubscribing) an episode is done
    /// only if it is in a playlist and in every playlist its podcast is assigned to. Partial
    /// auto-add (Sport: Unten, Politik: Aus) leaves it open for "Hinzufügen zu Politik".
    public static func isSortedByAutoAdd(inPlaylists: Set<PlaylistID>, podcastPlaylists: Set<PlaylistID>) -> Bool {
        !inPlaylists.isEmpty && podcastPlaylists.isSubset(of: inPlaylists)
    }

    /// Only an open episode becomes done or discarded; done is stored (N40), discarded stays out.
    public static func state(_ state: InboxState, after event: InboxEvent) -> InboxState {
        guard state == .open else { return state }
        switch event {
        case .handled: return .done
        case .discarded: return .discarded
        }
    }

    /// Episodes that arrived at or before this moment are no longer shown (A48). Arrival is
    /// exclusive here, while `entering` takes publication dates of exactly 14 days ago.
    public static func cutoff(now: Date) -> Date {
        now.addingTimeInterval(-retention)
    }

    /// Open, arrived within 14 days, podcast still subscribed (A48, A58, N74).
    public static func isShown(_ episode: InboxEpisode, now: Date) -> Bool {
        episode.state == .open && isRecent(episode, now: now)
    }

    /// The inbox as it shows: the open episodes, filtered, newest first (N53); equal dates keep
    /// their order.
    public static func shown(_ episodes: [InboxEpisode], filter: PlaylistFilter, now: Date) -> [InboxEpisode] {
        newestFirst(episodes.filter { isShown($0, now: now) && matches($0, filter) })
    }

    /// "Gerade erledigt" below the open episodes (N74, A67): done episodes that were seen open
    /// in this session, filtered and sorted like `shown`. Discarded ones are gone (N77).
    public static func recentlyDone(
        _ episodes: [InboxEpisode], seenOpen: Set<EpisodeID>, filter: PlaylistFilter, now: Date
    ) -> [InboxEpisode] {
        newestFirst(episodes.filter {
            $0.state == .done && seenOpen.contains($0.id) && isRecent($0, now: now) && matches($0, filter)
        })
    }

    /// The number on the tab (N41, N47): open episodes that arrived after the last visit,
    /// as far as "Alle" shows them (N65).
    public static func newCount(_ episodes: [InboxEpisode], lastVisit: Date?, now: Date) -> Int {
        episodes.count { episode in
            episode.state == .open && isShown(episode, now: now) && matches(episode, .all)
                && lastVisit.map { episode.addedAt > $0 } ?? true
        }
    }

    /// "Alle hinzufügen" on the shown episodes (A59): the open ones whose podcast has
    /// playlists, oldest first, so each goes to the bottom in chronological order.
    public static func episodesToAddAll(_ shown: [InboxEpisode]) -> [EpisodeID] {
        shown.enumerated()
            .filter { $0.element.state == .open && !$0.element.podcastPlaylists.isEmpty }
            .sorted { a, b in
                a.element.publishedAt != b.element.publishedAt
                    ? a.element.publishedAt < b.element.publishedAt : a.offset > b.offset
            }
            .map(\.element.id)
    }

    /// "Rest aussortieren" on the shown episodes (N78, A69): every open one, also those of
    /// podcasts without a playlist.
    public static func episodesToDiscardAll(_ shown: [InboxEpisode]) -> [EpisodeID] {
        shown.filter { $0.state == .open }.map(\.id)
    }

    /// Arrived within 14 days, podcast still subscribed (A48, A58).
    private static func isRecent(_ episode: InboxEpisode, now: Date) -> Bool {
        episode.addedAt > cutoff(now: now) && episode.podcastIsSubscribed
    }

    private static func newestFirst(_ episodes: [InboxEpisode]) -> [InboxEpisode] {
        episodes.enumerated()
            .sorted { a, b in
                a.element.publishedAt != b.element.publishedAt
                    ? a.element.publishedAt > b.element.publishedAt : a.offset < b.offset
            }
            .map(\.element)
    }

    private static func matches(_ episode: InboxEpisode, _ filter: PlaylistFilter) -> Bool {
        switch filter {
        case .all: !episode.podcastIsHidden
        case .playlist(let id): episode.podcastPlaylists.contains(id)
        case .withoutPlaylist: episode.podcastPlaylists.isEmpty
        }
    }
}
