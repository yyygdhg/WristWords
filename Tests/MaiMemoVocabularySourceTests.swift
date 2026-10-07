import Foundation
import XCTest

final class MaiMemoVocabularySourceTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func source(_ transport: StubVocabularyTransport, token: String = "fixture-credential") -> MaiMemoVocabularySource {
        MaiMemoVocabularySource(token: token, transport: transport, spellings: ["apple", "maintain"])
    }

    private func expectError(_ expected: VocabularyLoadError, from source: MaiMemoVocabularySource) async {
        do {
            _ = try await source.loadWords()
            XCTFail("Expected a safe data-source error")
        } catch let error as VocabularyLoadError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error category")
        }
    }

    func testOfficialEnvelopeMapsWordsAndPersonalInterpretations() async throws {
        let vocabulary = try fixture("maimemo-vocabulary")
        let interpretations = try fixture("maimemo-interpretations")
        let transport = StubVocabularyTransport { request in
            if request.httpMethod == "POST" { return (200, vocabulary) }
            let id = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value
            return (200, id == "fixture-voc-apple" ? interpretations : Data(#"{"interpretations":[]}"#.utf8))
        }

        let words = try await source(transport).loadWords()

        XCTAssertEqual(words, [
            VocabularyWord(id: "fixture-voc-apple", term: "apple", phonetic: "", meaning: "n. 苹果"),
            VocabularyWord(id: "fixture-voc-maintain", term: "maintain", phonetic: "", meaning: ""),
        ])
        XCTAssertEqual(transport.requests.count, 3)
        let query = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(query.url?.absoluteString, "https://open.maimemo.com/open/api/v1/memo/vocabulary/query")
        XCTAssertEqual(query.httpMethod, "POST")
        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(query.httpBody)) as? [String: [String]]
        XCTAssertEqual(body?["spellings"], ["apple", "maintain"])
        for request in transport.requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-credential")
            XCTAssertEqual(request.url?.host, "open.maimemo.com")
        }
        XCTAssertEqual(transport.requests[1].url?.path, "/open/api/v1/memo/interpretations")
    }

    func testBarePayloadAndMissingInterpretationContentDoNotInventFields() async throws {
        let transport = StubVocabularyTransport { request in
            let json = request.httpMethod == "POST"
                ? #"{"voc":[{"id":"fixture-1","spelling":"apple"}]}"#
                : #"{"interpretations":[{"status":"PUBLISHED"},{"interpretation":" ","status":"UNPUBLISHED"}]}"#
            return (200, Data(json.utf8))
        }

        let words = try await source(transport).loadWords()

        XCTAssertEqual(words.first?.term, "apple")
        XCTAssertEqual(words.first?.phonetic, "")
        XCTAssertEqual(words.first?.meaning, "")
    }

    func testIncompleteAndDuplicateVocabularyRowsAreSkipped() async throws {
        let transport = StubVocabularyTransport { request in
            let json = request.httpMethod == "POST"
                ? #"{"voc":[{}, {"id":"","spelling":"apple"}, {"id":"fixture-1"}, {"id":"fixture-2","spelling":" maintain "}, {"id":"fixture-2","spelling":"maintain"}]}"#
                : #"{"interpretations":[]}"#
            return (200, Data(json.utf8))
        }

        let words = try await source(transport).loadWords()

        XCTAssertEqual(words.map(\.term), ["maintain"])
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testNonemptyResponseWithoutAnyUsableWordIsAnError() async {
        let transport = StubVocabularyTransport { _ in (200, Data(#"{"voc":[{}, {"id":"fixture-1"}]}"#.utf8)) }
        await expectError(.invalidWordData, from: source(transport))
    }

    func testMalformedJSONAndUnexpectedTypesAreSafeDecodingErrors() async {
        for json in ["not json", #"{"voc":null}"#, #"{"voc":[{"id":4,"spelling":"apple"}]}"#, #"{"success":"yes","voc":[]}"#] {
            let transport = StubVocabularyTransport { _ in (200, Data(json.utf8)) }
            await expectError(.decoding, from: source(transport))
        }
    }

    func testMissingTokenMakesNoNetworkRequest() async {
        let transport = StubVocabularyTransport { _ in XCTFail("Should not send a request"); return (200, Data()) }
        await expectError(.missingToken, from: source(transport, token: " \n "))
        XCTAssertTrue(transport.requests.isEmpty)
    }

    func testInvalidCredentialMakesNoNetworkRequest() async {
        for token in ["fixture\r\nheader", "Bearer fixture-credential"] {
            let transport = StubVocabularyTransport { _ in XCTFail("Should not send a request"); return (200, Data()) }
            await expectError(.invalidToken, from: source(transport, token: token))
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }

    func testHTTPErrorsPreserveStatusWithoutReturningResponseContent() async {
        for status in [401, 403, 429, 500] {
            let transport = StubVocabularyTransport { _ in (status, Data("fixture-private-body".utf8)) }
            await expectError(.http(status), from: source(transport))
            XCTAssertFalse(VocabularyLoadError.http(status).message.contains("fixture-private-body"))
        }
    }

    func testNetworkErrorIsPassedAsASafeCategory() async {
        let transport = StubVocabularyTransport { _ in throw URLError(.notConnectedToInternet) }
        await expectError(.network(URLError.Code.notConnectedToInternet.rawValue), from: source(transport))
    }

    func testAPIFailureEnvelopeIsNotAcceptedAsSuccess() async {
        for json in [#"{"success":false,"data":{"voc":[]}}"#, #"{"success":true,"errors":[{"message":"fixture-rejection"}],"data":{"voc":[]}}"#] {
            let transport = StubVocabularyTransport { _ in (200, Data(json.utf8)) }
            await expectError(.apiRejected, from: source(transport))
        }
    }

    func testInterpretationRequestErrorsAreNotHidden() async {
        let transport = StubVocabularyTransport { request in
            if request.httpMethod == "POST" {
                return (200, Data(#"{"voc":[{"id":"fixture-1","spelling":"apple"}]}"#.utf8))
            }
            return (403, Data())
        }
        await expectError(.http(403), from: source(transport))
    }

    func testEmptyVocabularyResponseIsAValidEmptyList() async throws {
        let transport = StubVocabularyTransport { _ in (200, Data(#"{"voc":[]}"#.utf8)) }
        let words = try await source(transport).loadWords()
        XCTAssertTrue(words.isEmpty)
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testCancellationRemainsCancellation() async {
        let transport = StubVocabularyTransport { _ in throw URLError(.cancelled) }
        do {
            _ = try await source(transport).loadWords()
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertEqual(transport.requests.count, 1)
        } catch {
            XCTFail("Cancellation was changed into another error")
        }
    }
}

private final class StubVocabularyTransport: VocabularyHTTPTransport {
    private let handler: (URLRequest) throws -> (Int, Data)
    private(set) var requests: [URLRequest] = []

    init(handler: @escaping (URLRequest) throws -> (Int, Data)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, data) = try handler(request)
        let response = try XCTUnwrap(HTTPURLResponse(url: XCTUnwrap(request.url), statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil))
        return (data, response)
    }
}
