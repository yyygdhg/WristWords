import XCTest

final class StudySessionTests: XCTestCase {
    private let words = MockVocabulary.words

    func testStartsWithFirstWordAndZeroResults() {
        let session = StudySession(words: words)

        XCTAssertEqual(session.currentWord, words.first)
        XCTAssertEqual(session.totalCount, 5)
        XCTAssertEqual(session.completedCount, 0)
        XCTAssertTrue(session.results.isEmpty)
        XCTAssertFalse(session.isComplete)
    }

    func testEveryRatingRecordsCurrentWordAndAdvancesOnce() {
        for rating in StudyRating.allCases {
            var session = StudySession(words: words)

            session.rateCurrentWord(rating)

            XCTAssertEqual(session.results, [StudyResult(wordID: words[0].id, rating: rating)])
            XCTAssertEqual(session.completedCount, 1)
            XCTAssertEqual(session.currentWord, words[1])
            XCTAssertFalse(session.isComplete)
        }
    }

    func testFullReviewPreservesWordOrderAndRatingsThenCompletes() {
        var session = StudySession(words: words)
        let ratings: [StudyRating] = [.forgotten, .uncertain, .known, .uncertain, .known]

        for (index, word) in words.enumerated() {
            XCTAssertEqual(session.currentWord, word)
            XCTAssertEqual(session.completedCount, index)
            XCTAssertFalse(session.isComplete)
            session.rateCurrentWord(ratings[index])
        }

        XCTAssertNil(session.currentWord)
        XCTAssertTrue(session.isComplete)
        XCTAssertEqual(session.completedCount, session.totalCount)
        XCTAssertEqual(session.results.map(\.wordID), words.map(\.id))
        XCTAssertEqual(session.results.map(\.rating), ratings)
    }

    func testRatingAfterCompletionDoesNotRecordAnotherResult() {
        var session = StudySession(words: Array(words.prefix(1)))
        session.rateCurrentWord(.known)
        let completedResults = session.results

        session.rateCurrentWord(.forgotten)

        XCTAssertEqual(session.results, completedResults)
        XCTAssertEqual(session.completedCount, 1)
        XCTAssertTrue(session.isComplete)
        XCTAssertNil(session.currentWord)
    }

    func testRestartAfterCompletionClearsResultsAndAllowsAnotherReview() {
        var session = StudySession(words: words)
        for _ in words {
            session.rateCurrentWord(.known)
        }

        session.restart()

        XCTAssertEqual(session.currentWord, words.first)
        XCTAssertEqual(session.completedCount, 0)
        XCTAssertEqual(session.totalCount, words.count)
        XCTAssertTrue(session.results.isEmpty)
        XCTAssertFalse(session.isComplete)

        session.rateCurrentWord(.forgotten)
        XCTAssertEqual(session.currentWord, words[1])
        XCTAssertEqual(session.results, [StudyResult(wordID: words[0].id, rating: .forgotten)])
    }

    func testRestartDuringReviewReturnsToFirstWord() {
        var session = StudySession(words: words)
        session.rateCurrentWord(.uncertain)
        session.rateCurrentWord(.known)

        session.restart()

        XCTAssertEqual(session.currentWord, words.first)
        XCTAssertTrue(session.results.isEmpty)
        XCTAssertFalse(session.isComplete)
    }

    func testEmptySessionIsCompleteAndSafeToRateOrRestart() {
        var session = StudySession(words: [])

        XCTAssertTrue(session.isComplete)
        XCTAssertNil(session.currentWord)
        XCTAssertEqual(session.totalCount, 0)
        session.rateCurrentWord(.known)
        session.restart()
        XCTAssertTrue(session.isComplete)
        XCTAssertNil(session.currentWord)
        XCTAssertTrue(session.results.isEmpty)
    }

    func testSessionsKeepIndependentResults() {
        var first = StudySession(words: words)
        let second = StudySession(words: words)

        first.rateCurrentWord(.forgotten)

        XCTAssertEqual(first.completedCount, 1)
        XCTAssertEqual(second.completedCount, 0)
        XCTAssertEqual(second.currentWord, words.first)
        XCTAssertTrue(second.results.isEmpty)
    }
}
