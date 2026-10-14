import PodlistKit

/// UI tests (`-uiTesting`) never see the permission prompt and post nothing.
struct UITestNotificationCenter: NotificationCenterClient {
    func authorization() async -> NotificationAuthorization { .authorized }
    func requestAuthorization() async -> Bool { true }
    func post(_ notification: EpisodeNotification) async throws {}
}
