import Foundation
import XCTest
@testable import kk

private final class StubProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let chunk = "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\r\n\r\n"
        let second = "data: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\r\n\r\n"
        let body = url.path.contains("complete") ? chunk + second + "data: [DONE]\r\n\r\n" : chunk
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class OpenAICompatibleClientTests: XCTestCase {
    private func response(path: String) async throws -> String {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        let client = OpenAICompatibleClient(session: session)
        let config = APIConfiguration(baseURL: "https://example.test/\(path)", apiKey: "", model: "test")
        let request = ChatCompletionRequest(model: "test", messages: [], stream: true)
        var answer = ""
        for try await delta in client.streamCompletion(request: request, configuration: config) {
            answer += delta
        }
        return answer
    }

    func testCompleteStreamSucceeds() async throws {
        let answer = try await response(path: "complete")
        XCTAssertEqual(answer, "Hello world")
    }

    func testTruncatedStreamFails() async {
        do {
            _ = try await response(path: "truncated")
            XCTFail("A truncated response must not be reported as complete")
        } catch let error as KKError {
            guard case .streamFailed = error else { return XCTFail("Unexpected error: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
