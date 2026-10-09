import Foundation
import XCTest

final class StudyResultPayloadTests: XCTestCase {
    private func event(_ rating: StudyRating = .known, sequence: Int = 1,
                       wordID: String = "词汇-café-☕") -> StudyResultEvent {
        StudyResultEvent(result: StudyResult(wordID: wordID, rating: rating),
                         transferID: UUID(), sessionID: UUID(), sequence: sequence)
    }

    func testEveryRatingAndUnicodeRoundTripThroughPropertyList() throws {
        for rating in StudyRating.allCases {
            let original = event(rating)
            let info = try StudyResultPayload.encode(original)
            let data = try PropertyListSerialization.data(fromPropertyList: info, format: .binary, options: 0)
            let restored = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
            XCTAssertEqual(try StudyResultPayload.decode(restored), original)
            let json = try XCTUnwrap(info[StudyResultPayload.userInfoKey] as? Data)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
            let result = try XCTUnwrap(object["result"] as? [String: Any])
            XCTAssertEqual(result["rating"] as? String, rating.wireValue)
        }
    }

    func testEncoderRejectsInvalidSequenceAndBlankWordID() {
        for value in [event(sequence: 0), event(sequence: -1), event(wordID: " \n ")] {
            XCTAssertThrowsError(try StudyResultPayload.encode(value)) {
                XCTAssertEqual($0 as? StudyResultPayloadError, .invalidResult)
            }
        }
    }

    func testMissingCorruptAndWrongTypedPayloadsAreSafeErrors() throws {
        let valid = try JSONEncoder().encode(event())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: valid) as? [String: Any])
        var invalidUUID = object
        invalidUUID["sessionID"] = "not-a-uuid"
        var invalidRating = object
        invalidRating["result"] = ["wordID": "word", "rating": "unknown"]
        let payloads: [[String: Any]] = [
            [:], [StudyResultPayload.userInfoKey: "not-data"],
            [StudyResultPayload.userInfoKey: Data("not-json".utf8)],
            [StudyResultPayload.userInfoKey: Data("{}".utf8)],
            [StudyResultPayload.userInfoKey: try JSONSerialization.data(withJSONObject: invalidUUID)],
            [StudyResultPayload.userInfoKey: try JSONSerialization.data(withJSONObject: invalidRating)],
        ]
        for payload in payloads {
            XCTAssertThrowsError(try StudyResultPayload.decode(payload)) {
                XCTAssertEqual($0 as? StudyResultPayloadError, .invalidPayload)
            }
        }
    }

    func testUnknownVersionIsRejected() throws {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(event())) as? [String: Any])
        object["version"] = 2
        let info = [StudyResultPayload.userInfoKey: try JSONSerialization.data(withJSONObject: object)]
        XCTAssertThrowsError(try StudyResultPayload.decode(info)) {
            XCTAssertEqual($0 as? StudyResultPayloadError, .unsupportedVersion)
        }
    }

    func testDecoderAlsoValidatesSequenceAndWordID() throws {
        for value in [event(sequence: 0), event(wordID: "\n")] {
            let info = [StudyResultPayload.userInfoKey: try JSONEncoder().encode(value)]
            XCTAssertThrowsError(try StudyResultPayload.decode(info)) {
                XCTAssertEqual($0 as? StudyResultPayloadError, .invalidResult)
            }
        }
    }

    func testPayloadWhitelistContainsNoCredentialsOrSourceData() throws {
        let info = try StudyResultPayload.encode(event())
        XCTAssertEqual(Set(info.keys), [StudyResultPayload.userInfoKey])
        let data = try XCTUnwrap(info[StudyResultPayload.userInfoKey] as? Data)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["version", "id", "transferID", "sessionID", "sequence", "result"])
        let result = try XCTUnwrap(object["result"] as? [String: Any])
        XCTAssertEqual(Set(result.keys), ["wordID", "rating"])
    }
}
