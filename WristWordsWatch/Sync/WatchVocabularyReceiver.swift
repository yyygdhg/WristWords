import Foundation
import WatchConnectivity

@MainActor
final class WatchVocabularyReceiver: NSObject, WCSessionDelegate {
    private let model: WatchStudyModel

    init(model: WatchStudyModel) {
        self.model = model
        super.init()
        model.onResultsAvailable = { [weak self] in self?.flushResults() }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    private func flushResults() {
        model.enqueuePendingResults { event in
            guard WCSession.isSupported(),
                  WCSession.default.activationState == .activated else { return false }
            do {
                let userInfo = try StudyResultPayload.encode(event)
                // Every event is queued separately. No reachability guard,
                // application-context overwrite, or cancellation of earlier events.
                WCSession.default.transferUserInfo(userInfo)
                return true
            } catch {
                return false
            }
        }
    }

    nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer,
                             error: Error?) {
        guard error != nil, let event = try? StudyResultPayload.decode(userInfoTransfer.userInfo) else { return }
        Task { @MainActor [weak self] in self?.model.retainForRetry(event) }
    }

    private func receive(_ context: [String: Any]) {
        guard !context.isEmpty else { return }
        let accepted = model.receive(context)
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--wristwords-sync-smoke") {
            let report: [String: Any] = [
                "status": accepted ? "received" : "invalid-payload",
                "transferID": model.receivedTransferID?.uuidString ?? "",
                "wordCount": model.session.totalCount,
                "firstWordID": model.session.currentWord?.id ?? "",
            ]
            // Only enabled by the CI launch argument, with synthetic Mock data.
            let file = URL.documentsDirectory.appending(path: "watch-sync-probe.json")
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONSerialization.data(withJSONObject: report)
                try data.write(to: file, options: .atomic)
            } catch {
                print("CI Watch sync probe could not write its report.")
            }
        }
        #endif
    }

    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated && error == nil else { return }
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--wristwords-sync-smoke") {
            let report: [String: Any] = [
                "activationState": activationState.rawValue,
                "isCompanionAppInstalled": session.isCompanionAppInstalled,
            ]
            let file = URL.documentsDirectory.appending(path: "watch-session-probe.json")
            do {
                try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONSerialization.data(withJSONObject: report)
                try data.write(to: file, options: .atomic)
            } catch {
                print("CI Watch session probe could not write its report.")
            }
        }
        #endif
        let context = session.receivedApplicationContext
        Task { @MainActor [weak self] in
            self?.receive(context)
            self?.flushResults()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        Task { @MainActor [weak self] in
            self?.receive(context)
            self?.flushResults()
        }
    }
}
