import Foundation
import Synchronization
@testable import PodlistKit

/// Records posted notifications instead of showing them; the authorization is set by the test.
final class FakeNotificationCenter: NotificationCenterClient {
    private let state: Mutex<(authorization: NotificationAuthorization, grants: Bool, requests: Int, posted: [EpisodeNotification])>

    init(authorization: NotificationAuthorization = .authorized, grants: Bool = true) {
        state = Mutex((authorization, grants, 0, []))
    }

    var posted: [EpisodeNotification] { state.withLock { $0.posted } }
    /// How often the system prompt was shown.
    var authorizationRequests: Int { state.withLock { $0.requests } }

    func authorization() async -> NotificationAuthorization { state.withLock { $0.authorization } }

    func requestAuthorization() async -> Bool {
        state.withLock {
            $0.requests += 1
            $0.authorization = $0.grants ? .authorized : .denied
            return $0.grants
        }
    }

    func post(_ notification: EpisodeNotification) async throws {
        state.withLock { $0.posted.append(notification) }
    }
}
