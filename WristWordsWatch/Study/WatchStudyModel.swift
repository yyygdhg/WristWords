import Combine
import Foundation

@MainActor
final class WatchStudyModel: ObservableObject {
    @Published private(set) var session = StudySession(words: MockVocabulary.words)
    @Published private(set) var sourceName = "Mock"
    @Published private(set) var syncMessage: String?
    private(set) var receivedTransferID: UUID?

    @discardableResult
    func receive(_ context: [String: Any]) -> Bool {
        do {
            let snapshot = try VocabularySyncPayload.decode(context)
            // Restoring the same system context must not restart an active review.
            guard receivedTransferID != snapshot.transferID else { return true }
            session = StudySession(words: snapshot.words)
            receivedTransferID = snapshot.transferID
            sourceName = "iPhone"
            syncMessage = nil
            return true
        } catch {
            syncMessage = "同步数据无效，保留当前单词。"
            return false
        }
    }

    func rate(_ rating: StudyRating) {
        session.rateCurrentWord(rating)
    }

    func restart() {
        session.restart()
    }
}
