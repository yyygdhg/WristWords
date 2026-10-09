import Foundation

// An event wraps the existing StudyResult rather than duplicating word/rating data.
struct StudyResultEvent: Codable, Equatable, Identifiable {
    let version: Int
    let id: UUID
    let transferID: UUID
    let sessionID: UUID
    let sequence: Int
    let result: StudyResult

    init(result: StudyResult, transferID: UUID, sessionID: UUID,
         sequence: Int, id: UUID = UUID()) {
        version = 1
        self.id = id
        self.transferID = transferID
        self.sessionID = sessionID
        self.sequence = sequence
        self.result = result
    }
}

enum StudyResultPayloadError: Error, Equatable {
    case invalidPayload
    case unsupportedVersion
    case invalidResult
}

enum StudyResultPayload {
    static let userInfoKey = "studyResult"

    static func encode(_ event: StudyResultEvent) throws -> [String: Any] {
        try validate(event)
        do {
            return [userInfoKey: try JSONEncoder().encode(event)]
        } catch {
            throw StudyResultPayloadError.invalidPayload
        }
    }

    static func decode(_ userInfo: [String: Any]) throws -> StudyResultEvent {
        guard let data = userInfo[userInfoKey] as? Data else {
            throw StudyResultPayloadError.invalidPayload
        }
        let event: StudyResultEvent
        do {
            event = try JSONDecoder().decode(StudyResultEvent.self, from: data)
        } catch {
            throw StudyResultPayloadError.invalidPayload
        }
        try validate(event)
        return event
    }

    private static func validate(_ event: StudyResultEvent) throws {
        guard event.version == 1 else {
            throw StudyResultPayloadError.unsupportedVersion
        }
        guard event.sequence > 0,
              !event.result.wordID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw StudyResultPayloadError.invalidResult
        }
    }
}
