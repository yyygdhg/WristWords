import Combine
import Foundation

@MainActor
final class VocabularyListModel: ObservableObject {
    @Published private(set) var words: [VocabularyWord] = []
    @Published private(set) var sourceName = "Mock"
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var credentialMessage: String?
    @Published private(set) var hasSavedToken = false

    private let tokenStore: any TokenStore
    private let makeAPI: (String) -> any VocabularySource

    init(
        tokenStore: any TokenStore,
        makeAPI: @escaping (String) -> any VocabularySource = { MaiMemoVocabularySource(token: $0) }
    ) {
        self.tokenStore = tokenStore
        self.makeAPI = makeAPI
    }

    func start(source: any VocabularySource = MockVocabularySource()) async {
        refreshSavedTokenStatus()
        await load(source, sourceName: "Mock")
    }

    func useMock() async {
        await load(MockVocabularySource(), sourceName: "Mock")
    }

    func testConnection(tokenInput: String) async {
        guard !isLoading else { return }
        do {
            let draft = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
            let token = draft.isEmpty ? (try tokenStore.read() ?? "") : draft
            await load(makeAPI(token), sourceName: "MaiMemo API")
        } catch let error as TokenStoreError {
            errorMessage = error.message
        } catch {
            errorMessage = "无法读取本机凭证，请重新输入。"
        }
    }

    @discardableResult
    func saveToken(_ input: String) -> Bool {
        let token = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            credentialMessage = VocabularyLoadError.missingToken.message
            return false
        }
        do {
            try tokenStore.save(token)
            hasSavedToken = true
            credentialMessage = "已保存到本机 Keychain。"
            return true
        } catch let error as TokenStoreError {
            credentialMessage = error.message
        } catch {
            credentialMessage = "凭证保存失败，没有保存到明文文件。"
        }
        return false
    }

    func deleteToken() {
        do {
            try tokenStore.delete()
            hasSavedToken = false
            credentialMessage = "已删除本机保存的凭证。"
        } catch let error as TokenStoreError {
            credentialMessage = error.message
        } catch {
            credentialMessage = "无法删除本机凭证。"
        }
    }

    private func refreshSavedTokenStatus() {
        do {
            hasSavedToken = !(try tokenStore.read() ?? "").isEmpty
        } catch let error as TokenStoreError {
            credentialMessage = error.message
        } catch {
            credentialMessage = "无法检查本机凭证状态。"
        }
    }

    private func load(_ source: any VocabularySource, sourceName: String) async {
        guard !isLoading else { return }
        self.sourceName = sourceName
        words = []
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        do {
            words = try await source.loadWords()
        } catch is CancellationError {
            errorMessage = "加载已取消，可重新尝试。"
        } catch let error as VocabularyLoadError {
            errorMessage = error.message
        } catch {
            errorMessage = "加载失败，可切回 Mock 数据后重试。"
        }
    }
}
