import Foundation
import Observation
import SwiftData
import os

/// Categories of new-episode notifications; the app registers them with localized actions.
public enum NotificationCategory: String, CaseIterable, Sendable {
    /// Offers "Zu Playlists hinzufügen": an assigned playlist does not contain the episode (N34).
    case newEpisode
    /// The episode is in every assigned playlist already (or the podcast has none).
    case newEpisodeInPlaylists

    /// The actions of the category, in display order.
    public var actions: [NotificationAction] {
        switch self {
        case .newEpisode: [.addToPlaylists, .playNext, .playLast]
        case .newEpisodeInPlaylists: [.playNext, .playLast]
        }
    }
}

/// Actions of a new-episode notification (N34); all run in the background.
public enum NotificationAction: String, CaseIterable, Sendable {
    case addToPlaylists
    case playNext
    case playLast
}

/// Whether the app may show notifications.
public enum NotificationAuthorization: Sendable {
    case notDetermined
    case denied
    case authorized
}

/// One new-episode notification as a value, so it can cross into the system center.
public struct EpisodeNotification: Hashable, Sendable {
    public var episode: UUID
    public var podcast: UUID
    /// The podcast's title.
    public var title: String
    /// The episode's title.
    public var body: String
    public var category: NotificationCategory
    public var artworkURL: URL?
}

/// The system notification center, replaceable in tests.
public protocol NotificationCenterClient: Sendable {
    func authorization() async -> NotificationAuthorization
    /// Shows the system prompt; returns whether notifications are allowed.
    func requestAuthorization() async -> Bool
    func post(_ notification: EpisodeNotification) async throws
}

/// What the user did with a new-episode notification.
public enum NotificationResponse: Hashable, Sendable {
    /// Tapped: show the episode's details.
    case open(episode: UUID)
    case action(NotificationAction, episode: UUID)

    /// The key of the episode's `uuid` in a notification's `userInfo`.
    public static let episodeKey = "episode"
    /// `UNNotificationDefaultActionIdentifier`
    static let defaultActionIdentifier = "com.apple.UNNotificationDefaultActionIdentifier"

    /// Nil for anything else, e.g. the notification was dismissed.
    public init?(actionIdentifier: String, userInfo: [AnyHashable: Any]) {
        guard let string = userInfo[Self.episodeKey] as? String, let episode = UUID(uuidString: string) else { return nil }
        if actionIdentifier == Self.defaultActionIdentifier {
            self = .open(episode: episode)
        } else if let action = NotificationAction(rawValue: actionIdentifier) {
            self = .action(action, episode: episode)
        } else {
            return nil
        }
    }
}

/// A change in the notification settings that can be undone (N87): a group's switch or the
/// main switch. Only the latest one.
public struct NotificationUndoableChange: Identifiable, Equatable, Sendable {
    public enum Kind: Hashable, Sendable {
        case group(NotificationGroupID)
        /// The main switch.
        case all
    }

    public let id = UUID()
    public var kind: Kind
    /// What the switch was turned to.
    public var isOn: Bool
}

/// Posts a notification for new episodes of podcasts with notifications on (N34, N35, A45)
/// and asks for permission once a podcast wants them (A47). Owns the notification settings
/// (N87): the main switch and the switches of the groups, with one step of undo.
@MainActor @Observable
public final class NotificationScheduler {
    public private(set) var authorization: NotificationAuthorization = .notDetermined
    /// The main switch (N87): off posts nothing, and each podcast keeps its own value.
    public private(set) var isEnabled: Bool
    /// The latest group or main switch change, while it can be undone.
    public private(set) var undoableChange: NotificationUndoableChange?

    private enum UndoData {
        /// The former value of each podcast (`uuid`) the change touched.
        case podcasts([UUID: Bool])
        case enabled(Bool)
    }

    private enum SettingsKey {
        static let isEnabled = "notificationsEnabled"
    }

    private let context: ModelContext
    private let center: any NotificationCenterClient
    @ObservationIgnored private let settings: UserDefaults
    private let now: @Sendable () -> Date
    /// A prompt is showing; a second request (e.g. launch and subscribing) waits for nothing.
    private var isRequesting = false
    @ObservationIgnored private var undoData: UndoData?

    public init(
        context: ModelContext, center: any NotificationCenterClient, settings: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.context = context
        self.center = center
        self.settings = settings
        self.now = now
        settings.register(defaults: [SettingsKey.isEnabled: true])
        isEnabled = settings.bool(forKey: SettingsKey.isEnabled)
    }

    // MARK: Settings (N87)

    /// The main switch; it can be undone.
    public func setEnabled(_ isOn: Bool) {
        let before = isEnabled
        apply(isEnabled: isOn)
        remember(.enabled(before), as: NotificationUndoableChange(kind: .all, isOn: isOn))
        if isOn { requestAuthorizationSoon() }
    }

    /// The switch of a group: sets every subscribed podcast in it, also where it shows under
    /// another playlist. It can be undone; undo restores each podcast's former value.
    public func setNotificationsEnabled(_ isOn: Bool, for group: NotificationGroupID) throws {
        let podcasts = try subscribedPodcasts()
        let members = Set(NotificationGroups.members(of: group, among: podcasts.map(\.notificationPodcast)).map(\.uuid))
        var before: [UUID: Bool] = [:]
        for podcast in podcasts where members.contains(podcast.uuid) {
            before[podcast.uuid] = podcast.notificationsEnabled
            podcast.notificationsEnabled = isOn
        }
        try context.save()
        remember(.podcasts(before), as: NotificationUndoableChange(kind: .group(group), isOn: isOn))
        if isOn { requestAuthorizationSoon() }
    }

    /// A podcast's own switch in the settings: not undoable, and it ends the undo of a group,
    /// so that undo never overwrites it.
    public func setNotificationsEnabled(_ isOn: Bool, for podcast: Podcast) throws {
        dismissUndo()
        podcast.notificationsEnabled = isOn
        try context.save()
        if isOn { requestAuthorizationSoon() }
    }

    public func undo() throws {
        guard let data = undoData else { return }
        dismissUndo()
        switch data {
        case .enabled(let isOn):
            apply(isEnabled: isOn)
        case .podcasts(let before):
            for podcast in try subscribedPodcasts() {
                if let isOn = before[podcast.uuid] { podcast.notificationsEnabled = isOn }
            }
            try context.save()
        }
    }

    public func dismissUndo() {
        undoableChange = nil
        undoData = nil
    }

    private func apply(isEnabled isOn: Bool) {
        isEnabled = isOn
        settings.set(isOn, forKey: SettingsKey.isEnabled)
        Logger.notifications.info("Notifications \(isOn ? "on" : "off", privacy: .public)")
    }

    private func remember(_ data: UndoData, as change: NotificationUndoableChange) {
        undoData = data
        undoableChange = change
    }

    private func requestAuthorizationSoon() {
        Task { await requestAuthorizationIfNeeded() }
    }

    private func subscribedPodcasts() throws -> [Podcast] {
        try context.fetch(FetchDescriptor<Podcast>(predicate: #Predicate { $0.isSubscribed }))
    }

    // MARK: Posting

    /// Notifies the new episodes (`uuid`s from a refresh) the rules pick.
    public func notifyNewEpisodes(_ ids: [UUID]) async {
        guard !ids.isEmpty, isEnabled else { return }
        await updateAuthorization()
        guard authorization == .authorized else { return }
        do {
            for notification in try notifications(for: ids) {
                try await center.post(notification)
            }
        } catch {
            Logger.notifications.error("Posting notifications failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Asks for permission if the main switch is on, a subscribed podcast has notifications on
    /// and the user was not asked yet (A47).
    public func requestAuthorizationIfNeeded() async {
        guard !isRequesting, isEnabled else { return }
        isRequesting = true
        defer { isRequesting = false }
        await updateAuthorization()
        guard authorization == .notDetermined else { return }
        let wanted = FetchDescriptor<Podcast>(predicate: #Predicate { $0.isSubscribed && $0.notificationsEnabled })
        guard (try? context.fetchCount(wanted)) ?? 0 > 0 else { return }
        let granted = await center.requestAuthorization()
        authorization = granted ? .authorized : .denied
        Logger.notifications.info("Notifications \(granted ? "allowed" : "not allowed", privacy: .public)")
    }

    public func updateAuthorization() async {
        authorization = await center.authorization()
    }

    private func notifications(for ids: [UUID]) throws -> [EpisodeNotification] {
        let episodes = try context.fetch(FetchDescriptor<Episode>(predicate: #Predicate { ids.contains($0.uuid) }))
        let byID = Dictionary(episodes.map { ($0.episodeID, $0) }, uniquingKeysWith: { first, _ in first })
        let candidates = ids.compactMap { id -> NewEpisodeCandidate? in
            guard let episode = byID[EpisodeID(id)], let podcast = episode.podcast else { return nil }
            return NewEpisodeCandidate(
                episode: episode.episodeID, podcast: PodcastID(podcast.uuid), publishedAt: episode.publishedAt,
                notificationsEnabled: podcast.isSubscribed && podcast.notificationsEnabled)
        }
        return NewEpisodeNotifications.episodesToNotify(candidates, now: now()).compactMap { id in
            guard let episode = byID[id], let podcast = episode.podcast else { return nil }
            let missing = NewEpisodeNotifications.playlistsToAdd(
                assigned: (podcast.assignments ?? []).compactMap { $0.playlist?.playlistID },
                containing: Set((episode.playlistEntries ?? []).compactMap { $0.playlist?.playlistID }))
            return EpisodeNotification(
                episode: episode.uuid, podcast: podcast.uuid, title: podcast.title, body: episode.title,
                category: missing.isEmpty ? .newEpisodeInPlaylists : .newEpisode, artworkURL: podcast.artworkURL)
        }
    }
}
