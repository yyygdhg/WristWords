import XCTest

final class WatchStudyModelTests: XCTestCase {
    @MainActor
    func testNoSyncUsesTheExistingMockFallback() {
        let model = WatchStudyModel()
        XCTAssertEqual(model.sourceName, "Mock")
        XCTAssertEqual(model.session.currentWord, MockVocabulary.words.first)
        XCTAssertEqual(model.session.totalCount, 5)
        XCTAssertNil(model.receivedTransferID)
    }

    @MainActor
    func testReceivedWordsStartANewSessionFromTheFirstWord() throws {
        let words = Array(MockVocabulary.words.reversed())
        let snapshot = VocabularySnapshot(words: words)
        let model = WatchStudyModel()
        XCTAssertTrue(model.receive(try VocabularySyncPayload.encode(snapshot)))
        XCTAssertEqual(model.session.currentWord, words.first)
        XCTAssertEqual(model.session.totalCount, words.count)
        XCTAssertEqual(model.session.completedCount, 0)
        XCTAssertEqual(model.sourceName, "iPhone")
        XCTAssertEqual(model.receivedTransferID, snapshot.transferID)
    }

    @MainActor
    func testNewSnapshotReplacesAnOngoingSessionAndItsResults() throws {
        let model = WatchStudyModel()
        XCTAssertTrue(model.receive(try VocabularySyncPayload.encode(VocabularySnapshot(words: MockVocabulary.words))))
        model.rate(.uncertain)
        let newWords = Array(MockVocabulary.words.suffix(2))
        XCTAssertTrue(model.receive(try VocabularySyncPayload.encode(VocabularySnapshot(words: newWords))))
        XCTAssertEqual(model.session.currentWord, newWords.first)
        XCTAssertEqual(model.session.totalCount, 2)
        XCTAssertTrue(model.session.results.isEmpty)
    }

    @MainActor
    func testDuplicateDeliveryDoesNotResetProgress() throws {
        let context = try VocabularySyncPayload.encode(VocabularySnapshot(words: MockVocabulary.words))
        let model = WatchStudyModel()
        model.receive(context)
        model.rate(.known)
        XCTAssertTrue(model.receive(context))
        XCTAssertEqual(model.session.completedCount, 1)
        XCTAssertEqual(model.session.currentWord, MockVocabulary.words[1])
        XCTAssertEqual(model.session.results.first?.rating, .known)
    }

    @MainActor
    func testInvalidPayloadKeepsTheCurrentSessionAndResults() throws {
        let model = WatchStudyModel()
        model.receive(try VocabularySyncPayload.encode(VocabularySnapshot(words: MockVocabulary.words)))
        model.rate(.forgotten)
        let id = model.receivedTransferID
        XCTAssertFalse(model.receive([VocabularySyncPayload.contextKey: "invalid"]))
        XCTAssertEqual(model.receivedTransferID, id)
        XCTAssertEqual(model.sourceName, "iPhone")
        XCTAssertEqual(model.session.currentWord, MockVocabulary.words[1])
        XCTAssertEqual(model.session.results.first?.rating, .forgotten)
        XCTAssertNotNil(model.syncMessage)
    }

    @MainActor
    func testEmptySnapshotIsSafeWithoutFallingBackToUnsentWords() throws {
        let model = WatchStudyModel()
        XCTAssertTrue(model.receive(try VocabularySyncPayload.encode(VocabularySnapshot(words: []))))
        XCTAssertEqual(model.sourceName, "iPhone")
        XCTAssertEqual(model.session.totalCount, 0)
        XCTAssertTrue(model.session.isComplete)
        model.rate(.known)
        model.restart()
        XCTAssertNil(model.session.currentWord)
        XCTAssertTrue(model.session.results.isEmpty)
    }

    @MainActor
    func testReceivedSessionSupportsRatingsCompletionAndRestart() throws {
        let words = Array(MockVocabulary.words.prefix(2))
        let model = WatchStudyModel()
        model.receive(try VocabularySyncPayload.encode(VocabularySnapshot(words: words)))
        model.rate(.uncertain)
        XCTAssertEqual(model.session.currentWord, words[1])
        model.rate(.known)
        XCTAssertTrue(model.session.isComplete)
        XCTAssertEqual(model.session.results.map(\.rating), [.uncertain, .known])
        model.restart()
        XCTAssertEqual(model.session.currentWord, words.first)
        XCTAssertTrue(model.session.results.isEmpty)
        XCTAssertEqual(model.sourceName, "iPhone")
    }
}
