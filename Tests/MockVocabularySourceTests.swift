import XCTest

final class MockVocabularySourceTests: XCTestCase {
    func testMockSourceKeepsOriginalVocabulary() async throws {
        let source: any VocabularySource = MockVocabularySource()

        let words = try await source.loadWords()

        XCTAssertEqual(words, MockVocabulary.words)
        XCTAssertEqual(words.count, 5)
        XCTAssertTrue(words.allSatisfy { !$0.phonetic.isEmpty && !$0.meaning.isEmpty })
    }

    func testLoadedWordsCanBeUsedByStudySession() async throws {
        let words = try await MockVocabularySource().loadWords()
        var session = StudySession(words: words)

        XCTAssertEqual(session.currentWord, words.first)
        session.rateCurrentWord(.known)
        XCTAssertEqual(session.currentWord, words[1])
        XCTAssertEqual(session.completedCount, 1)
    }
}
