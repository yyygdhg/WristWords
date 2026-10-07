import Foundation

enum VocabularyLoadError: Error, Equatable {
    case missingToken
    case invalidToken
    case network(Int)
    case http(Int)
    case invalidResponse
    case decoding
    case apiRejected
    case invalidWordData

    var message: String {
        switch self {
        case .missingToken: return "没有 Token。请粘贴墨墨请求凭证，或先保存到本机 Keychain。"
        case .invalidToken: return "凭证格式异常。请粘贴原始请求凭证，不要包含换行或 Bearer 前缀。"
        case .network: return "网络请求失败，请检查连接后重试。"
        case .http(let status): return "HTTP 错误：\(status)。401/403 请检查凭证，429 请稍后重试。"
        case .invalidResponse: return "服务器返回了无效的 HTTP 响应。"
        case .decoding: return "JSON 解析失败，响应字段与官方规范不一致。"
        case .apiRejected: return "墨墨 API 返回失败状态。请检查凭证及接口权限。"
        case .invalidWordData: return "响应中没有可用的单词 ID 和拼写。"
        }
    }
}

protocol VocabularyHTTPTransport {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

final class URLSessionVocabularyTransport: VocabularyHTTPTransport {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw VocabularyLoadError.invalidResponse
        }
        return (data, http)
    }
}

struct MaiMemoVocabularySource: VocabularySource {
    // Small, public query inputs; results are always read from the official API.
    static let sampleSpellings = ["engagement", "maintain", "abandon", "significant", "approach"]

    private let token: String
    private let transport: any VocabularyHTTPTransport
    private let spellings: [String]

    init(
        token: String,
        transport: any VocabularyHTTPTransport = URLSessionVocabularyTransport(),
        spellings: [String] = sampleSpellings
    ) {
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
        self.spellings = spellings
    }

    func loadWords() async throws -> [VocabularyWord] {
        guard !token.isEmpty else { throw VocabularyLoadError.missingToken }
        guard token.rangeOfCharacter(from: .controlCharacters) == nil,
              !token.lowercased().hasPrefix("bearer ") else {
            throw VocabularyLoadError.invalidToken
        }

        var query = try request(path: "vocabulary/query")
        query.httpMethod = "POST"
        query.httpBody = try JSONEncoder().encode(QueryRequest(spellings: spellings))
        let response: VocabularyResponse = try await send(query)

        var seenIDs = Set<String>()
        let valid = response.voc.compactMap { row -> (id: String, spelling: String)? in
            guard let id = row.id?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
                  let spelling = row.spelling?.trimmingCharacters(in: .whitespacesAndNewlines), !spelling.isEmpty,
                  seenIDs.insert(id).inserted else { return nil }
            return (id, spelling)
        }
        if !response.voc.isEmpty && valid.isEmpty {
            throw VocabularyLoadError.invalidWordData
        }

        var words: [VocabularyWord] = []
        for row in valid {
            try Task.checkCancellation()
            let query = try request(path: "interpretations", query: [URLQueryItem(name: "voc_id", value: row.id)])
            let response: InterpretationsResponse = try await send(query)
            var seenMeanings = Set<String>()
            let meanings = response.interpretations.compactMap { entry -> String? in
                guard entry.status == "PUBLISHED" || entry.status == "UNPUBLISHED",
                      let text = entry.interpretation?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty, seenMeanings.insert(text).inserted else { return nil }
                return text
            }
            words.append(VocabularyWord(id: row.id, term: row.spelling, phonetic: "", meaning: meanings.joined(separator: "；")))
        }
        return words
    }

    private func request(path: String, query: [URLQueryItem] = []) throws -> URLRequest {
        // Paths and field names come from https://open.maimemo.com/api_bundle.yaml.
        var components = URLComponents(string: "https://open.maimemo.com/open/api/v1/memo/" + path)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw VocabularyLoadError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func send<Value: Decodable>(_ request: URLRequest) async throws -> Value {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VocabularyLoadError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw VocabularyLoadError.network(error.code.rawValue)
        } catch {
            throw VocabularyLoadError.network(-1)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw VocabularyLoadError.http(response.statusCode)
        }
        do {
            return try JSONDecoder().decode(APIResponse<Value>.self, from: data).value
        } catch let error as VocabularyLoadError {
            throw error
        } catch {
            // Never propagate raw bodies, headers or decoder diagnostics to UI/logs.
            throw VocabularyLoadError.decoding
        }
    }
}

private struct QueryRequest: Encodable { let spellings: [String] }
private struct VocabularyResponse: Decodable { let voc: [VocabularyDTO] }
private struct VocabularyDTO: Decodable { let id: String?; let spelling: String? }
private struct InterpretationsResponse: Decodable { let interpretations: [InterpretationDTO] }
private struct InterpretationDTO: Decodable { let interpretation: String?; let status: String? }

private struct APIResponse<Value: Decodable>: Decodable {
    let value: Value
    private enum CodingKeys: String, CodingKey { case success, errors, data }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decodeIfPresent(Bool.self, forKey: .success) == false {
            throw VocabularyLoadError.apiRejected
        }
        if container.contains(.errors), try !container.decodeNil(forKey: .errors) {
            let errors = try container.nestedUnkeyedContainer(forKey: .errors)
            if !errors.isAtEnd { throw VocabularyLoadError.apiRejected }
        }
        // Official CLI supports both the data envelope and a bare payload.
        if container.contains(.data) {
            value = try container.decode(Value.self, forKey: .data)
        } else {
            value = try Value(from: decoder)
        }
    }
}
