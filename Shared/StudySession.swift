enum StudyRating: String, CaseIterable, Identifiable {
    case forgotten = "忘记"
    case uncertain = "模糊"
    case known = "认识"

    var id: Self { self }
}

struct StudyResult: Equatable {
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
