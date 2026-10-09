import Foundation
import XCTest

final class WatchResultSyncTests: XCTestCase {
    @MainActor
    private func receivedModel(words: [VocabularyWord] = MockVocabulary.words) throws -> (WatchStudyModel, VocabularySnapshot) {
        let model = WatchStudyModel()
        let snapshot = VocabularySnapshot(words: words)
        XCTAssertTrue(model.receive(try VocabularySyncPayload.encode(snapshot)))
        return (model, snapshot)
    }

    @MainActor
    func testRatingAdvancesStudyAndCreatesDistinctAssociatedEvents() throws {
        let (model, snapshot) = try receivedModel()
        let sessionID = model.studySessionID
        for rating in StudyRating.allCases { model.rate(rating) }
        XCTAssertEqual(model.session.completedCount, 3)
        XCTAssertEqual(model.session.currentWord, MockVocabulary.words[3])
        XCTAssertEqual(model.pendingResults.map(\.result), model.session.results)
        XCTAssertEqual(model.pendingResults.map(\.sequence), [1, 2, 3])
        XCTAssertEqual(Set(model.pendingResults.map(\.id)).count, 3)
        XCTAssertTrue(model.pendingResults.allSatisfy {
            $0.transferID == snapshot.transferID && $0.sessionID == sessionID
        })
    }

    @MainActor
    func testFallbackRatingsRemainLocalWithoutInventingASnapshot() {
        let model = WatchStudyModel()
        XCTAssertNil(model.rate(.known))
        XCTAssertEqual(model.session.completedCount, 1)
        XCTAssertEqual(model.session.results[0].rating, .known)
        XCTAssertTrue(model.pendingResults.isEmpty)
    }

    @MainActor
    func testRestartCreatesNewSessionAndKeepsEarlierEvents() throws {
        let (model, snapshot) = try receivedModel()
        let first = try XCTUnwrap(model.rate(.known))
        model.restart()
        let second = try XCTUnwrap(model.rate(.forgotten))
        XCTAssertEqual(first.transferID, snapshot.transferID)
        XCTAssertEqual(second.transferID, first.transferID)
        XCTAssertNotEqual(second.sessionID, first.sessionID)
        XCTAssertNotEqual(second.id, first.id)
        XCTAssertEqual(second.sequence, 1)
        XCTAssertEqual(second.result.wordID, first.result.wordID)
        XCTAssertEqual(model.pendingResults, [first, second])
    }

    @MainActor
    func testDuplicateSnapshotKeepsSessionIDAndPendingResults() throws {
        let (model, snapshot) = try receivedModel()
        let first = try XCTUnwrap(model.rate(.known))
        model.receive(try VocabularySyncPayload.encode(snapshot))
        let second = try XCTUnwrap(model.rate(.uncertain))
        XCTAssertEqual(second.sessionID, first.sessionID)
        XCTAssertEqual(second.sequence, 2)
        XCTAssertEqual(model.pendingResults, [first, second])
    }

    @MainActor
    func testNewSnapshotDoesNotDiscardOldPendingEvents() throws {
        let (model, a) = try receivedModel()
        let first = try XCTUnwrap(model.rate(.known))
        let b = VocabularySnapshot(words: Array(MockVocabulary.words.reversed()))
        model.receive(try VocabularySyncPayload.encode(b))
        let second = try XCTUnwrap(model.rate(.forgotten))
        XCTAssertEqual(first.transferID, a.transferID)
        XCTAssertEqual(second.transferID, b.transferID)
        XCTAssertNotEqual(second.sessionID, first.sessionID)
        XCTAssertEqual(second.sequence, 1)
        XCTAssertEqual(model.pendingResults, [first, second])
    }

    @MainActor
    func testInactiveTransportRetainsAllEventsWhileStudyCanFinish() throws {
        let (model, _) = try receivedModel()
        for _ in MockVocabulary.words { model.rate(.known) }
        let original = model.pendingResults
        model.enqueuePendingResults { _ in false }
        XCTAssertEqual(model.pendingResults, original)
        XCTAssertTrue(model.session.isComplete)
        var handedOff: [StudyResultEvent] = []
        model.enqueuePendingResults { handedOff.append($0); return true }
        XCTAssertEqual(handedOff, original)
        XCTAssertTrue(model.pendingResults.isEmpty)
        XCTAssertEqual(model.session.results.count, 5)
    }

    @MainActor
    func testPartialHandoffKeepsUnqueuedEventsAndTheirIDsForRetry() throws {
        let (model, _) = try receivedModel()
        model.rate(.known)
        model.rate(.uncertain)
        model.rate(.forgotten)
        let original = model.pendingResults
        model.enqueuePendingResults { $0.id == original[0].id }
        XCTAssertEqual(model.pendingResults, Array(original.dropFirst()))
        var retry: [StudyResultEvent] = []
        model.enqueuePendingResults { retry.append($0); return true }
        XCTAssertEqual(retry, Array(original.dropFirst()))
        XCTAssertTrue(model.pendingResults.isEmpty)
    }

    @MainActor
    func testFailedNativeTransferCanRetryTheSameEventWithoutRepeatingLocalStudy() throws {
        let (model, _) = try receivedModel()
        let value = try XCTUnwrap(model.rate(.known))
        model.enqueuePendingResults { _ in true }
        model.retainForRetry(value)
        model.retainForRetry(value)
        XCTAssertEqual(model.pendingResults, [value])
        XCTAssertEqual(model.session.completedCount, 1)
        var retried: StudyResultEvent?
        model.enqueuePendingResults { retried = $0; return true }
        XCTAssertEqual(retried, value)
        XCTAssertTrue(model.pendingResults.isEmpty)
        XCTAssertEqual(model.session.results.count, 1)
    }

    @MainActor
    func testEmptyOrCompletedSessionDoesNotCreateExtraEvents() throws {
        let (empty, _) = try receivedModel(words: [])
        XCTAssertNil(empty.rate(.known))
        XCTAssertTrue(empty.pendingResults.isEmpty)
        let (single, _) = try receivedModel(words: [MockVocabulary.words[0]])
        single.rate(.known)
        XCTAssertNil(single.rate(.forgotten))
        XCTAssertEqual(single.pendingResults.count, 1)
        XCTAssertEqual(single.session.results.count, 1)
    }
}
