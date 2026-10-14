import Foundation

/// A subscribed podcast as the notification settings see it.
public struct NotificationPodcast: Hashable, Sendable {
    public var id: PodcastID
    public var title: String
    public var isOn: Bool
    /// Its playlists; "Alles" is none of them.
    public var playlists: Set<PlaylistID>

    public init(id: PodcastID, title: String, isOn: Bool, playlists: Set<PlaylistID>) {
        self.id = id
        self.title = title
        self.isOn = isOn
        self.playlists = playlists
    }
}

/// A group in the notification settings: a playlist or the podcasts without one.
public enum NotificationGroupID: Hashable, Sendable {
    case playlist(PlaylistID)
    case withoutPlaylist
}

/// A group's switch is on only when all its podcasts are; otherwise it shows how many are.
public enum NotificationGroupState: Hashable, Sendable {
    case on
    case off
    case mixed(on: Int, of: Int)
}

public struct NotificationGroup: Hashable, Sendable, Identifiable {
    public var id: NotificationGroupID
    /// Sorted by title.
    public var podcasts: [PodcastID]
    public var state: NotificationGroupState
}

/// Settings → Benachrichtigungen (concept §4.10, N87): the podcasts nested under their
/// playlists. `shown` are the visible playlists in their order, then the podcasts without a
/// playlist; `hidden` are the hidden playlists, behind "Mehr ›" (N66). A podcast in several
/// playlists shows under each, with one switch. Groups without podcasts are left out.
public enum NotificationGroups {
    public static func groups(
        podcasts: [NotificationPodcast], playlists: [(id: PlaylistID, isHidden: Bool)]
    ) -> (shown: [NotificationGroup], hidden: [NotificationGroup]) {
        let sorted = podcasts.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        let split = HiddenPlaylists.split(playlists)
        let group = { (id: NotificationGroupID) -> NotificationGroup? in
            let members = sorted.filter { isMember($0, of: id) }
            guard !members.isEmpty else { return nil }
            return NotificationGroup(id: id, podcasts: members.map(\.id), state: state(of: members))
        }
        let shown = (split.shown.map(NotificationGroupID.playlist) + [.withoutPlaylist]).compactMap(group)
        return (shown, split.behindMore.map(NotificationGroupID.playlist).compactMap(group))
    }

    /// The podcasts a group's switch turns on or off, in input order.
    public static func members(of group: NotificationGroupID, among podcasts: [NotificationPodcast]) -> [PodcastID] {
        podcasts.filter { isMember($0, of: group) }.map(\.id)
    }

    private static func isMember(_ podcast: NotificationPodcast, of group: NotificationGroupID) -> Bool {
        switch group {
        case .playlist(let id): podcast.playlists.contains(id)
        case .withoutPlaylist: podcast.playlists.isEmpty
        }
    }

    private static func state(of podcasts: [NotificationPodcast]) -> NotificationGroupState {
        let on = podcasts.count(where: \.isOn)
        if on == podcasts.count { return .on }
        return on == 0 ? .off : .mixed(on: on, of: podcasts.count)
    }
}
