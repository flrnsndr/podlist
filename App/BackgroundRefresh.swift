import BackgroundTasks
import Foundation
import PodlistKit
import os

/// Refreshing feeds in the background (A44): iOS runs the task when it sees fit, at most
/// every 15 minutes; every run and every trip to the background schedules the next one.
nonisolated enum BackgroundRefresh {
    /// Also listed under `BGTaskSchedulerPermittedIdentifiers` in `Podlist-Info.plist`.
    static let identifier = "com.podlistapp.podlist.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: RefreshSchedule.backgroundInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // E.g. in the simulator or with Background App Refresh turned off.
            Logger.feeds.notice("Scheduling the background refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
