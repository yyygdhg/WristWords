import Foundation
import XCTest

final class VocabularySyncPayloadTests: XCTestCase {
    func testWordCodablePreservesAllFields() throws {
        let word = VocabularyWord(id: "unicode-1", term: "café", phonetic: "/kæˈfeɪ/", meaning: "咖啡馆；含中文与 emoji ☕")
        XCTAssertEqual(try JSONDecoder().decode(VocabularyWord.self, from: JSONEncoder().encode(word)), word)
    }

    func testMultipleWordsRoundTripThroughPropertyListContext() throws {
        let snapshot = VocabularySnapshot(words: MockVocabulary.words)
        let context = try VocabularySyncPayload.encode(snapshot)
        let plist = try PropertyListSerialization.data(fromPropertyList: context, format: .binary, options: 0)
        let restored = try XCTUnwrap(PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any])
        XCTAssertEqual(try VocabularySyncPayload.decode(restored), snapshot)
    }

    func testEmptyListIsAValidSnapshot() throws {
        let snapshot = VocabularySnapshot(words: [])
        XCTAssertEqual(try VocabularySyncPayload.decode(VocabularySyncPayload.encode(snapshot)).words, [])
    }

    func testWordsWithoutAPIPhoneticsOrMeaningsRemainUsable() throws {
        let word = VocabularyWord(id: "api-fixture", term: "approach", phonetic: "", meaning: "")
        let snapshot = VocabularySnapshot(words: [word])
        XCTAssertEqual(try VocabularySyncPayload.decode(VocabularySyncPayload.encode(snapshot)).words, [word])
    }

    func testEncodingRejectsBlankIdentifiersTermsAndDuplicateIdentifiers() {
        let word = MockVocabulary.words[0]
        for words in [[VocabularyWord(id: " ", term: "word", phonetic: "", meaning: "")],
                      [VocabularyWord(id: "id", term: "\n", phonetic: "", meaning: "")], [word, word]] {
            XCTAssertThrowsError(try VocabularySyncPayload.encode(VocabularySnapshot(words: words))) {
                XCTAssertEqual($0 as? VocabularySyncPayloadError, .invalidWords)
            }
        }
    }

    func testInvalidContextsAreSafeErrors() {
        let contexts: [[String: Any]] = [[:], [VocabularySyncPayload.contextKey: "not-data"],
                                       [VocabularySyncPayload.contextKey: Data("not-json".utf8)],
                                       [VocabularySyncPayload.contextKey: Data("{\"words\":42}".utf8)]]
        for context in contexts {
            XCTAssertThrowsError(try VocabularySyncPayload.decode(context)) {
                XCTAssertEqual($0 as? VocabularySyncPayloadError, .invalidPayload)
            }
        }
    }

    func testUnsupportedFormatIsRejected() throws {
        let snapshot = VocabularySnapshot(words: MockVocabulary.words)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        object["version"] = 2
        let context = [VocabularySyncPayload.contextKey: try JSONSerialization.data(withJSONObject: object)]
        XCTAssertThrowsError(try VocabularySyncPayload.decode(context)) {
            XCTAssertEqual($0 as? VocabularySyncPayloadError, .unsupportedVersion)
        }
    }

    func testReceivedDuplicateIdentifiersAreRejected() throws {
        let word = MockVocabulary.words[0]
        let data = try JSONEncoder().encode(VocabularySnapshot(words: [word, word]))
        XCTAssertThrowsError(try VocabularySyncPayload.decode([VocabularySyncPayload.contextKey: data])) {
            XCTAssertEqual($0 as? VocabularySyncPayloadError, .invalidWords)
        }
    }

    func testPayloadContainsOnlyVocabularyAndSnapshotMetadata() throws {
        let context = try VocabularySyncPayload.encode(VocabularySnapshot(words: MockVocabulary.words))
        XCTAssertEqual(Set(context.keys), [VocabularySyncPayload.contextKey])
        let data = try XCTUnwrap(context[VocabularySyncPayload.contextKey] as? Data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "transferID", "words"])
        let words = try XCTUnwrap(object["words"] as? [[String: Any]])
        for word in words {
            XCTAssertEqual(Set(word.keys), ["id", "term", "phonetic", "meaning"])
        }
    }
}
