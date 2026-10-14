import Foundation
import UniformTypeIdentifiers
import UserNotifications
import os

/// `UNUserNotificationCenter` behind `NotificationCenterClient`. A notification shows the
/// podcast's artwork if it can be loaded within a few seconds (A45).
public struct SystemNotificationCenter: NotificationCenterClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func authorization() async -> NotificationAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        default: .authorized
        }
    }

    public func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            Logger.notifications.error("Requesting authorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    public func post(_ notification: EpisodeNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.threadIdentifier = notification.podcast.uuidString
        content.categoryIdentifier = notification.category.rawValue
        content.userInfo = [NotificationResponse.episodeKey: notification.episode.uuidString]
        if let url = notification.artworkURL, let attachment = await artwork(url) {
            content.attachments = [attachment]
        }
        let request = UNNotificationRequest(identifier: notification.episode.uuidString, content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
    }

    /// The artwork as a temporary file; the system moves it into its own storage.
    private func artwork(_ url: URL) async -> UNNotificationAttachment? {
        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 5)
            let (data, response) = try await session.data(for: request)
            let type = response.mimeType.flatMap { UTType(mimeType: $0) } ?? .jpeg
            guard type.conforms(to: .image), let fileExtension = type.preferredFilenameExtension else { return nil }
            let file = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).\(fileExtension)")
            try data.write(to: file)
            return try UNNotificationAttachment(identifier: "artwork", url: file)
        } catch {
            Logger.notifications.notice("No artwork for the notification: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}
