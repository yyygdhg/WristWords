enum StudyRating: String, CaseIterable, Identifiable, Codable {
    case forgotten = "忘记"
    case uncertain = "模糊"
    case known = "认识"

    var id: Self { self }

    // Keep the existing Chinese UI labels, with stable codes on the wire.
    var wireValue: String {
        switch self {
        case .forgotten: return "forgotten"
        case .uncertain: return "uncertain"
        case .known: return "known"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "forgotten": self = .forgotten
        case "uncertain": self = .uncertain
        case "known": self = .known
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown study rating")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wireValue)
    }
}

struct StudyResult: Equatable, Codable {
    let wordID: String
    let rating: StudyRating
}

struct StudySession {
    private let words: [VocabularyWord]
    private(set) var results: [StudyResult] = []

    init(words: [VocabularyWord]) {
        self.words = words
    }

    var totalCount: Int { words.count }
    var completedCount: Int { results.count }
    var isComplete: Bool { completedCount == totalCount }

    var currentWord: VocabularyWord? {
        guard !isComplete else { return nil }
        return words[completedCount]
    }

    mutating func rateCurrentWord(_ rating: StudyRating) {
        guard let word = currentWord else { return }
        results.append(StudyResult(wordID: word.id, rating: rating))
    }

    mutating func restart() {
        results.removeAll()
    }
}
