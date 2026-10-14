import PodlistKit
import SwiftData
import SwiftUI
import UserNotifications
import os

/// Receives new-episode notifications (N34): a tap shows the episode's details, the actions
/// add it to its playlists or to Up Next in the background. Registers the categories with
/// their localized actions.
@MainActor @Observable
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    /// The episode whose details show after a tap.
    var shownEpisode: NotifiedEpisode?

    private let context: ModelContext
    private let playlists: PlaylistService
    private let upNext: UpNextService

    init(context: ModelContext, playlists: PlaylistService, upNext: UpNextService) {
        self.context = context
        self.playlists = playlists
        self.upNext = upNext
        super.init()
    }

    /// Becomes the center's delegate; has to happen before the app finishes launching, so
    /// that a response which launched the app arrives here.
    func activate() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(Set(NotificationCategory.allCases.map(Self.category)))
    }

    // MARK: UNUserNotificationCenterDelegate

    /// A46: in the foreground no banner, only the notification center.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.list]
    }

    /// Not the `async` variant: its completion handler runs off the main thread, and UIKit
    /// aborts on that for a tap that opens the app.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping @Sendable () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let parsed = NotificationResponse(actionIdentifier: response.actionIdentifier, userInfo: userInfo)
        Task { @MainActor in
            if let parsed { handle(parsed) }
            completionHandler()
        }
    }

    private func handle(_ response: NotificationResponse) {
        switch response {
        case .open(let id):
            showDetails(of: id)
        case .action(let action, let id):
            guard let episode = episode(id) else { return }
            switch action {
            case .addToPlaylists:
                do {
                    try playlists.addToAssignedPlaylists(episode)
                } catch {
                    Logger.notifications.error("Adding to playlists failed: \(String(describing: error), privacy: .public)")
                }
            case .playNext: upNext.playNext(episode)
            case .playLast: upNext.playLast(episode)
            }
        }
    }

    /// The details are a sheet on the root view, which cannot present while another sheet
    /// (player, episode details, settings) is open; that one closes first.
    private func showDetails(of id: UUID) {
        let root = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.rootViewController }.first
        guard let root, root.presentedViewController != nil else {
            shownEpisode = NotifiedEpisode(id: id)
            return
        }
        root.dismiss(animated: true) { [weak self] in
            self?.shownEpisode = NotifiedEpisode(id: id)
        }
    }

    private func episode(_ id: UUID) -> Episode? {
        var descriptor = FetchDescriptor<Episode>(predicate: #Predicate { $0.uuid == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: Categories

    private static func category(_ category: NotificationCategory) -> UNNotificationCategory {
        UNNotificationCategory(identifier: category.rawValue, actions: category.actions.map(action), intentIdentifiers: [])
    }

    private static func action(_ action: NotificationAction) -> UNNotificationAction {
        let (title, symbol) = switch action {
        // Its own key: "Add to Playlists" is the title of the "In welche Playlists?" sheet.
        case .addToPlaylists:
            (String(localized: "notificationAction.addToPlaylists", defaultValue: "Add to Playlists"), "text.badge.plus")
        case .playNext: (String(localized: "Play Next"), "text.line.first.and.arrowtriangle.forward")
        case .playLast: (String(localized: "Play Last"), "text.line.last.and.arrowtriangle.forward")
        }
        return UNNotificationAction(
            identifier: action.rawValue, title: title, icon: UNNotificationActionIcon(systemImageName: symbol))
    }
}

/// The episode of a tapped notification.
struct NotifiedEpisode: Identifiable {
    let id: UUID
}

/// The details of the episode a tapped notification is about.
struct NotifiedEpisodeView: View {
    @Query private var episodes: [Episode]

    init(id: UUID) {
        _episodes = Query(filter: #Predicate<Episode> { $0.uuid == id })
    }

    var body: some View {
        if let episode = episodes.first {
            EpisodeDetailView(episode: episode)
        } else {
            ContentUnavailableView("Episode Not Available", systemImage: "exclamationmark.triangle")
        }
    }
}
