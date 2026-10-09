import Combine
import Foundation

@MainActor
final class WatchResultsModel: ObservableObject {
    @Published private(set) var results: [StudyResultEvent] = []
    @Published private(set) var statusMessage = "尚未收到 Watch 评价。"
    private var snapshots: [UUID: [VocabularyWord]] = [:]

    func register(_ snapshot: VocabularySnapshot) {
        snapshots[snapshot.transferID] = snapshot.words
    }

    var snapshotIDs: [UUID] {
        results.reduce(into: [UUID]()) { ids, event in
            if !ids.contains(event.transferID) { ids.append(event.transferID) }
        }
    }

    func results(for transferID: UUID) -> [StudyResultEvent] {
        let batch = results.filter { $0.transferID == transferID }
        let sessions = batch.reduce(into: [UUID]()) { ids, event in
            if !ids.contains(event.sessionID) { ids.append(event.sessionID) }
        }
        return sessions.flatMap { id in
            batch.filter { $0.sessionID == id }.sorted { $0.sequence < $1.sequence }
        }
    }

    func term(for event: StudyResultEvent) -> String {
        snapshots[event.transferID]?.first { $0.id == event.result.wordID }?.term ?? event.result.wordID
    }

    @discardableResult
    func receive(_ userInfo: [String: Any]) -> Bool {
        do {
            let event = try StudyResultPayload.decode(userInfo)
            if let existing = results.first(where: { $0.id == event.id }) {
                guard existing == event else { return reject() }
                statusMessage = "重复评价已忽略。"
                return true
            }
            // A review session belongs to exactly one snapshot. One sequence
            // position cannot record two different events, even with new IDs.
            let sessionResults = results.filter { $0.sessionID == event.sessionID }
            guard sessionResults.allSatisfy({ $0.transferID == event.transferID }),
                  !sessionResults.contains(where: { $0.sequence == event.sequence }) else {
                return reject()
            }
            if let words = snapshots[event.transferID] {
                guard event.sequence <= words.count,
                      words[event.sequence - 1].id == event.result.wordID else {
                    return reject()
                }
            }
            // Delayed events from before an iPhone restart remain separate by
            // transferID. If its in-memory word list is absent, display wordID.
            results.append(event)
            statusMessage = "已收到 \(results.count) 条 Watch 评价。"
            return true
        } catch {
            return reject()
        }
    }

    private func reject() -> Bool {
        statusMessage = "无效或冲突的 Watch 评价已忽略。"
        return false
    }
}
