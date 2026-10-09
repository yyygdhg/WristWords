import Foundation
import XCTest

final class WatchResultsModelTests: XCTestCase {
    private let words = Array(MockVocabulary.words.prefix(3))

    private func event(snapshot: VocabularySnapshot, sessionID: UUID, sequence: Int,
                       rating: StudyRating = .known, id: UUID = UUID()) -> StudyResultEvent {
        StudyResultEvent(result: StudyResult(wordID: snapshot.words[sequence - 1].id, rating: rating),
                         transferID: snapshot.transferID, sessionID: sessionID, sequence: sequence, id: id)
    }

    @MainActor
    func testMultipleResultsKeepEveryRatingAndResolveWords() throws {
        let model = WatchResultsModel()
        let snapshot = VocabularySnapshot(words: words)
        model.register(snapshot)
        let sessionID = UUID()
        let events = StudyRating.allCases.enumerated().map {
            event(snapshot: snapshot, sessionID: sessionID, sequence: $0.offset + 1, rating: $0.element)
        }
        for value in events { XCTAssertTrue(model.receive(try StudyResultPayload.encode(value))) }
        XCTAssertEqual(model.results, events)
        XCTAssertEqual(model.results.map { model.term(for: $0) }, words.map(\.term))
        XCTAssertEqual(model.results.map(\.result.rating), StudyRating.allCases)
    }

    @MainActor
    func testRepeatedCallbackRecordsTheEventOnlyOnce() throws {
        let model = WatchResultsModel()
        let snapshot = VocabularySnapshot(words: words)
        let value = event(snapshot: snapshot, sessionID: UUID(), sequence: 1)
        let payload = try StudyResultPayload.encode(value)
        XCTAssertTrue(model.receive(payload))
        XCTAssertTrue(model.receive(payload))
        XCTAssertEqual(model.results, [value])
    }

    @MainActor
    func testReusingAnEventIDWithDifferentContentDoesNotChangeTheResult() throws {
        let model = WatchResultsModel()
        let snapshot = VocabularySnapshot(words: words)
        let value = event(snapshot: snapshot, sessionID: UUID(), sequence: 1)
        model.receive(try StudyResultPayload.encode(value))
        let conflict = event(snapshot: snapshot, sessionID: value.sessionID, sequence: 1,
                             rating: .forgotten, id: value.id)
        XCTAssertFalse(model.receive(try StudyResultPayload.encode(conflict)))
        XCTAssertEqual(model.results, [value])
    }

    @MainActor
    func testSameSessionSequenceCannotBeCountedWithANewEventID() throws {
        let model = WatchResultsModel()
        let snapshot = VocabularySnapshot(words: words)
        let sessionID = UUID()
        let value = event(snapshot: snapshot, sessionID: sessionID, sequence: 1)
        model.receive(try StudyResultPayload.encode(value))
        XCTAssertFalse(model.receive(try StudyResultPayload.encode(
            event(snapshot: snapshot, sessionID: sessionID, sequence: 1))))
        XCTAssertEqual(model.results, [value])
    }

    @MainActor
    func testAReviewSessionCannotSwitchSnapshots() throws {
        let model = WatchResultsModel()
        let a = VocabularySnapshot(words: words)
        let b = VocabularySnapshot(words: words)
        let sessionID = UUID()
        let value = event(snapshot: a, sessionID: sessionID, sequence: 1)
        model.receive(try StudyResultPayload.encode(value))
        XCTAssertFalse(model.receive(try StudyResultPayload.encode(
            event(snapshot: b, sessionID: sessionID, sequence: 2))))
        XCTAssertEqual(model.results, [value])
    }

    @MainActor
    func testDelayedOldSnapshotResultsRemainSeparateFromNewSnapshot() throws {
        let model = WatchResultsModel()
        let a = VocabularySnapshot(words: words)
        let b = VocabularySnapshot(words: Array(words.reversed()))
        model.register(a)
        let aSession = UUID()
        let firstA = event(snapshot: a, sessionID: aSession, sequence: 1)
        model.receive(try StudyResultPayload.encode(firstA))
        model.register(b)
        let firstB = event(snapshot: b, sessionID: UUID(), sequence: 1)
        model.receive(try StudyResultPayload.encode(firstB))
        let delayedA = event(snapshot: a, sessionID: aSession, sequence: 2)
        model.receive(try StudyResultPayload.encode(delayedA))
        XCTAssertEqual(model.snapshotIDs, [a.transferID, b.transferID])
        XCTAssertEqual(model.results(for: a.transferID), [firstA, delayedA])
        XCTAssertEqual(model.results(for: b.transferID), [firstB])
        XCTAssertEqual(model.term(for: firstA), a.words[0].term)
        XCTAssertEqual(model.term(for: firstB), b.words[0].term)
    }

    @MainActor
    func testOutOfOrderArrivalDisplaysInSessionSequence() throws {
        let model = WatchResultsModel()
        let snapshot = VocabularySnapshot(words: words)
        model.register(snapshot)
        let sessionID = UUID()
        let first = event(snapshot: snapshot, sessionID: sessionID, sequence: 1)
        let second = event(snapshot: snapshot, sessionID: sessionID, sequence: 2)
        model.receive(try StudyResultPayload.encode(second))
        model.receive(try StudyResultPayload.encode(first))
        XCTAssertEqual(model.results(for: snapshot.transferID), [first, second])
    }

    @MainActor
    func testDelayedEventAfterPhoneRestartCanUseWordIDWithoutOldWordList() throws {
        let model = WatchResultsModel()
        let snapshot = VocabularySnapshot(words: words)
        let value = event(snapshot: snapshot, sessionID: UUID(), sequence: 1)
        XCTAssertTrue(model.receive(try StudyResultPayload.encode(value)))
        XCTAssertEqual(model.term(for: value), value.result.wordID)
        XCTAssertEqual(model.snapshotIDs, [snapshot.transferID])
        XCTAssertTrue(model.receive(try StudyResultPayload.encode(value)))
        XCTAssertEqual(model.results.count, 1)
    }

    @MainActor
    func testInvalidAndUnknownVersionDoNotPolluteExistingResults() throws {
        let model = WatchResultsModel()
        let snapshot = VocabularySnapshot(words: words)
        let value = event(snapshot: snapshot, sessionID: UUID(), sequence: 1)
        model.receive(try StudyResultPayload.encode(value))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        object["version"] = 999
        let unknown = [StudyResultPayload.userInfoKey: try JSONSerialization.data(withJSONObject: object)]
        let invalidPayloads: [[String: Any]] = [[:], [StudyResultPayload.userInfoKey: "bad"], unknown]
        for invalid in invalidPayloads {
            XCTAssertFalse(model.receive(invalid))
            XCTAssertEqual(model.results, [value])
        }
    }

    @MainActor
    func testKnownSnapshotRejectsWrongWordPositionAndOutOfRangeSequence() throws {
        let model = WatchResultsModel()
        let snapshot = VocabularySnapshot(words: words)
        model.register(snapshot)
        for result in [
            StudyResultEvent(result: StudyResult(wordID: words[1].id, rating: .known),
                             transferID: snapshot.transferID, sessionID: UUID(), sequence: 1),
            StudyResultEvent(result: StudyResult(wordID: "unknown", rating: .known),
                             transferID: snapshot.transferID, sessionID: UUID(), sequence: 1),
            StudyResultEvent(result: StudyResult(wordID: words[0].id, rating: .known),
                             transferID: snapshot.transferID, sessionID: UUID(), sequence: 4),
        ] {
            XCTAssertFalse(model.receive(try StudyResultPayload.encode(result)))
            XCTAssertTrue(model.results.isEmpty)
        }
    }

    @MainActor
    func testRestartedReviewUsesAnotherSessionWithinTheSameSnapshot() throws {
        let model = WatchResultsModel()
        let snapshot = VocabularySnapshot(words: words)
        let first = event(snapshot: snapshot, sessionID: UUID(), sequence: 1)
        let restarted = event(snapshot: snapshot, sessionID: UUID(), sequence: 1, rating: .uncertain)
        model.receive(try StudyResultPayload.encode(first))
        model.receive(try StudyResultPayload.encode(restarted))
        XCTAssertEqual(model.results(for: snapshot.transferID), [first, restarted])
        XCTAssertEqual(model.snapshotIDs, [snapshot.transferID])
    }
}
