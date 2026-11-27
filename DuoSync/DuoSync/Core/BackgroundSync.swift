import Foundation
import BackgroundTasks

/// Periodic background refresh, so folders keep moving while the app is closed.
@MainActor
enum BackgroundSync {
    static let identifier = "com.ross.duosync.refresh"

    /// Must be called before the app finishes launching.
    static func register(_ manager: SyncManager) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refresh, manager: manager)
        }
    }

    private static func handle(_ task: BGAppRefreshTask, manager: SyncManager) {
        schedule()
        let work = Task { @MainActor in
            await manager.syncAll(silent: true)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
        }
    }

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Background refresh is a nicety; foreground sync still covers it.
        }
    }
}
