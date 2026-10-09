import Foundation
import WatchConnectivity
import WatchKit

// Complete native WC background tasks after the received content is handled.
final class WatchConnectivityBackgroundDelegate: NSObject, WKApplicationDelegate {
    private var tasks: [WKWatchConnectivityRefreshBackgroundTask] = []
    private var observations: [NSKeyValueObservation] = []

    override init() {
        super.init()
        let session = WCSession.default
        observations = [
            session.observe(\.activationState) { [weak self] _, _ in
                DispatchQueue.main.async { self?.completeTasksIfReady() }
            },
            session.observe(\.hasContentPending) { [weak self] _, _ in
                DispatchQueue.main.async { self?.completeTasksIfReady() }
            },
        ]
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let connectivityTask = task as? WKWatchConnectivityRefreshBackgroundTask {
                tasks.append(connectivityTask)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
        completeTasksIfReady()
    }

    private func completeTasksIfReady() {
        let session = WCSession.default
        guard session.activationState != .activated || !session.hasContentPending else { return }
        tasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
        tasks.removeAll()
    }
}
