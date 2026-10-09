import Combine
import Foundation
import WatchConnectivity

@MainActor
final class PhoneVocabularySender: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var statusMessage = "正在连接 Apple Watch…"
    private(set) var failureReason = "activating"

    override init() {
        super.init()
        guard WCSession.isSupported() else {
            failureReason = "unsupported"
            statusMessage = "此设备不支持 WatchConnectivity。"
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    @discardableResult
    func send(words: [VocabularyWord]) -> UUID? {
        guard isReady() else { return nil }
        do {
            let snapshot = VocabularySnapshot(words: words)
            let context = try VocabularySyncPayload.encode(snapshot)
            // No reachability guard: the system can deliver the latest context
            // later, when the Watch is not currently in the foreground.
            try WCSession.default.updateApplicationContext(context)
            failureReason = ""
            statusMessage = "已提交 \(words.count) 个单词，等待 Watch 接收。"
            return snapshot.transferID
        } catch is VocabularySyncPayloadError {
            failureReason = "invalid-payload"
            statusMessage = "单词数据无效，未发送。"
        } catch {
            failureReason = "transport-error"
            statusMessage = "同步提交失败，请稍后重试。"
        }
        return nil
    }

    private func isReady() -> Bool {
        guard WCSession.isSupported() else {
            failureReason = "unsupported"
            statusMessage = "此设备不支持 WatchConnectivity。"
            return false
        }
        let session = WCSession.default
        guard session.activationState == .activated else {
            failureReason = "not-activated"
            statusMessage = "Watch 连接尚未就绪，请稍后重试。"
            return false
        }
        guard session.isPaired else {
            failureReason = "not-paired"
            statusMessage = "Watch 不可用：iPhone 尚未配对 Apple Watch。"
            return false
        }
        guard session.isWatchAppInstalled else {
            failureReason = "watch-app-not-installed"
            statusMessage = "Watch 不可用：请先安装 WristWords Watch App。"
            return false
        }
        return true
    }

    nonisolated func session(
        _ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        let succeeded = activationState == .activated && error == nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            if succeeded {
                if self.isReady() { self.statusMessage = "Apple Watch 连接已就绪。" }
            } else {
                self.failureReason = "activation-failed"
                self.statusMessage = "Watch 连接激活失败，请稍后重试。"
            }
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.isReady() { self.statusMessage = "Apple Watch 连接已就绪。" }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.failureReason = "inactive"
            self?.statusMessage = "Watch 连接正在切换，请稍后重试。"
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
