import Foundation

struct VocabularySnapshot: Codable, Equatable {
    let version: Int
    let transferID: UUID
    let words: [VocabularyWord]

    init(words: [VocabularyWord], transferID: UUID = UUID()) {
        version = 1
        self.transferID = transferID
        self.words = words
    }
}

enum VocabularySyncPayloadError: Error, Equatable {
    case invalidPayload
    case unsupportedVersion
    case invalidWords
}

enum VocabularySyncPayload {
    static let contextKey = "vocabularySnapshot"

    // Data is property-list compatible. Only these word fields and snapshot
    // metadata are encoded; data sources and credentials never enter this API.
    static func encode(_ snapshot: VocabularySnapshot) throws -> [String: Any] {
        try validate(snapshot)
        do {
            return [contextKey: try JSONEncoder().encode(snapshot)]
        } catch {
            throw VocabularySyncPayloadError.invalidPayload
        }
    }

    static func decode(_ context: [String: Any]) throws -> VocabularySnapshot {
        guard let data = context[contextKey] as? Data else {
            throw VocabularySyncPayloadError.invalidPayload
        }
        let snapshot: VocabularySnapshot
        do {
            snapshot = try JSONDecoder().decode(VocabularySnapshot.self, from: data)
        } catch {
            throw VocabularySyncPayloadError.invalidPayload
        }
        try validate(snapshot)
        return snapshot
    }

    private static func validate(_ snapshot: VocabularySnapshot) throws {
        guard snapshot.version == 1 else {
            throw VocabularySyncPayloadError.unsupportedVersion
        }
        var ids = Set<String>()
        for word in snapshot.words {
            guard !word.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !word.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  ids.insert(word.id).inserted else {
                throw VocabularySyncPayloadError.invalidWords
            }
        }
    }
}
