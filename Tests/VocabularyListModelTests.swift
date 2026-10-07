import XCTest

final class VocabularyListModelTests: XCTestCase {
    @MainActor
    func testStartUsesMockEvenWhenATokenIsAlreadyStored() async {
        let store = InMemoryTestTokenStore(token: "fixture-stored-credential")
        let model = VocabularyListModel(tokenStore: store) { _ in
            XCTFail("App launch must not automatically request the API")
            return MockVocabularySource()
        }

        await model.start()

        XCTAssertEqual(model.words, MockVocabulary.words)
        XCTAssertEqual(model.sourceName, "Mock")
        XCTAssertTrue(model.hasSavedToken)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testSavedCredentialIsUsedOnlyWhenConnectionIsRequested() async {
        let store = InMemoryTestTokenStore()
        var requestedCredential: String?
        let model = VocabularyListModel(tokenStore: store) { token in
            requestedCredential = token
            return MockVocabularySource()
        }

        XCTAssertTrue(model.saveToken(" fixture-local-credential\n"))
        XCTAssertNil(requestedCredential)
        XCTAssertEqual(store.token, "fixture-local-credential")
        await model.testConnection(tokenInput: "")

        XCTAssertEqual(requestedCredential, "fixture-local-credential")
        XCTAssertEqual(model.sourceName, "MaiMemo API")
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testTypedCredentialTakesPrecedenceWithoutPersistingIt() async {
        let store = InMemoryTestTokenStore(token: "fixture-old-credential")
        var requestedCredential: String?
        let model = VocabularyListModel(tokenStore: store) { token in
            requestedCredential = token
            return MockVocabularySource()
        }

        await model.testConnection(tokenInput: "fixture-temporary-credential")

        XCTAssertEqual(requestedCredential, "fixture-temporary-credential")
        XCTAssertEqual(store.token, "fixture-old-credential")
    }

    @MainActor
    func testDeleteRemovesSavedCredential() async {
        let store = InMemoryTestTokenStore(token: "fixture-stored-credential")
        let model = VocabularyListModel(tokenStore: store)
        await model.start()

        model.deleteToken()

        XCTAssertNil(store.token)
        XCTAssertFalse(model.hasSavedToken)
    }

    @MainActor
    func testMissingCredentialShowsErrorAndCanFallBackToMock() async {
        let model = VocabularyListModel(tokenStore: InMemoryTestTokenStore())

        await model.testConnection(tokenInput: "")

        XCTAssertEqual(model.errorMessage, VocabularyLoadError.missingToken.message)
        XCTAssertTrue(model.words.isEmpty)
        XCTAssertFalse(model.isLoading)
        await model.useMock()
        XCTAssertEqual(model.words, MockVocabulary.words)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.sourceName, "Mock")
    }

    @MainActor
    func testNetworkFailureProducesAnErrorState() async {
        let model = VocabularyListModel(tokenStore: InMemoryTestTokenStore()) { _ in
            FailingVocabularySource()
        }

        await model.testConnection(tokenInput: "fixture-credential")

        XCTAssertEqual(model.errorMessage, VocabularyLoadError.network(-1009).message)
        XCTAssertTrue(model.words.isEmpty)
        XCTAssertFalse(model.isLoading)
    }

    @MainActor
    func testStorageFailureIsReportedWithoutPlaintextFallback() async {
        let store = InMemoryTestTokenStore()
        store.saveError = .keychain(-34018)
        let model = VocabularyListModel(tokenStore: store) { _ in MockVocabularySource() }

        XCTAssertFalse(model.saveToken("fixture-credential"))
        XCTAssertNil(store.token)
        XCTAssertFalse(model.hasSavedToken)
        XCTAssertEqual(model.credentialMessage, TokenStoreError.keychain(-34018).message)
        await model.testConnection(tokenInput: "fixture-temporary-credential")
        XCTAssertNil(model.errorMessage)
        XCTAssertNil(store.token)
    }
}

private final class InMemoryTestTokenStore: TokenStore {
    var token: String?
    var saveError: TokenStoreError?

    init(token: String? = nil) { self.token = token }
    func read() throws -> String? { token }
    func save(_ token: String) throws {
        if let saveError { throw saveError }
        self.token = token
    }
    func delete() throws { token = nil }
}

private struct FailingVocabularySource: VocabularySource {
    func loadWords() async throws -> [VocabularyWord] {
        throw VocabularyLoadError.network(-1009)
    }
}
