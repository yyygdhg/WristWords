protocol VocabularySource {
    func loadWords() async throws -> [VocabularyWord]
}

struct MockVocabularySource: VocabularySource {
    func loadWords() async throws -> [VocabularyWord] {
        MockVocabulary.words
    }
}
