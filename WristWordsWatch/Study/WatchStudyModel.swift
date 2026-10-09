import Combine
import Foundation

@MainActor
final class WatchStudyModel: ObservableObject {
    @Published private(set) var session = StudySession(words: MockVocabulary.words)
    @Published private(set) var sourceName = "Mock"
    @Published private(set) var syncMessage: String?
    @Published private(set) var resultSyncMessage: String?
    @Published private(set) var pendingResults: [StudyResultEvent] = []
    private(set) var receivedTransferID: UUID?
    private(set) var studySessionID = UUID()
    var onResultsAvailable: (() -> Void)?

    @discardableResult
    func receive(_ context: [String: Any]) -> Bool {
        do {
            let snapshot = try VocabularySyncPayload.decode(context)
            // Restoring the same system context must not restart an active review.
            guard receivedTransferID != snapshot.transferID else { return true }
            session = StudySession(words: snapshot.words)
            receivedTransferID = snapshot.transferID
            studySessionID = UUID()
            sourceName = "iPhone"
            syncMessage = nil
            // Pending events retain their original batch/session when words change.
            return true
        } catch {
            syncMessage = "同步数据无效，保留当前单词。"
            return false
        }
    }

    @discardableResult
    func rate(_ rating: StudyRating) -> StudyResultEvent? {
        guard session.currentWord != nil else { return nil }
        session.rateCurrentWord(rating)
        guard let transferID = receivedTransferID, let result = session.results.last else {
            resultSyncMessage = "Mock fallback 评价仅保留在 Watch。"
            return nil
        }
        let event = StudyResultEvent(result: result, transferID: transferID,
                                     sessionID: studySessionID, sequence: session.completedCount)
        pendingResults.append(event)
        resultSyncMessage = "等待将评价加入后台队列。"
        onResultsAvailable?()
        return event
    }

    // Remove only after handing an event to the OS queue. A temporarily inactive
    // WCSession leaves all unsent events here, with the same IDs for a retry.
    func enqueuePendingResults(using enqueue: (StudyResultEvent) -> Bool) {
        var queued = 0
        while let event = pendingResults.first {
            guard enqueue(event) else { break }
            pendingResults.removeFirst()
            queued += 1
        }
        if !pendingResults.isEmpty {
            resultSyncMessage = "\(pendingResults.count) 条评价等待后台排队。"
        } else if queued > 0 {
            resultSyncMessage = "评价已加入后台队列，等待 iPhone 接收。"
        }
    }

    func retainForRetry(_ event: StudyResultEvent) {
        if !pendingResults.contains(where: { $0.id == event.id }) {
            pendingResults.append(event)
        }
        resultSyncMessage = "后台传输失败，评价已保留，请重试。"
    }

    func retryPendingResults() {
        onResultsAvailable?()
    }

    func restart() {
        session.restart()
        studySessionID = UUID()
    }
}
