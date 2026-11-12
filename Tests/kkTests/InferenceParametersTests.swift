import Foundation
import XCTest
@testable import kk

private final class ParameterProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            return data
        } ?? Data()
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let rejects = request.url!.path.contains("reject") && json["reasoning_effort"] != nil
        let response = HTTPURLResponse(url: request.url!, statusCode: rejects ? 400 : 200, httpVersion: nil, headerFields: [:])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let output = rejects ? "{\"error\":{\"message\":\"unsupported effort\"}}" : "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\ndata: [DONE]\n\n"
        client?.urlProtocol(self, didLoad: Data(output.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class InferenceParametersTests: XCTestCase {
    func testValidationAndTypedRequestBody() throws {
        for invalid in ["[]", "null", "{", "{\"model\":\"override\"}", "{\"stream\":false}", "{\" \":1}"] {
            XCTAssertThrowsError(try InferenceParameters.parse(invalid), invalid)
        }
        var config = APIConfiguration(baseURL: "https://example.test/v1", apiKey: "", model: "model")
        config.reasoningEffort = "low"
        config.customParameters = "{\"temperature\":0.7,\"enabled\":true,\"stop\":[\"END\"],\"nested\":{\"budget\":12},\"nullable\":null}"
        let request = try OpenAICompatibleClient().makeURLRequest(request: .init(model: "model", messages: [], stream: true), configuration: config)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "model")
        XCTAssertEqual(json["reasoning_effort"] as? String, "low")
        XCTAssertEqual(json["temperature"] as? Double, 0.7)
        XCTAssertEqual(json["enabled"] as? Bool, true)
        XCTAssertEqual(json["stop"] as? [String], ["END"])
        XCTAssertEqual((json["nested"] as? [String: Int])?["budget"], 12)
        XCTAssertTrue(json["nullable"] is NSNull)
    }

    func testCustomReasoningOverridesPickerIncludingNullAndOff() throws {
        let client = OpenAICompatibleClient()
        for selected in [nil, "low"] as [String?] {
            for custom in ["\"high\"", "null"] {
                var config = APIConfiguration(baseURL: "https://example.test/v1", apiKey: "", model: "test")
                config.reasoningEffort = selected
                config.customParameters = "{\"reasoning_effort\":\(custom),\"temperature\":0.3}"
                let request = try client.makeURLRequest(request: .init(model: "test", messages: [], stream: true), configuration: config)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
                if custom == "null" { XCTAssertTrue(json["reasoning_effort"] is NSNull) }
                else { XCTAssertEqual(json["reasoning_effort"] as? String, "high") }
                XCTAssertEqual(json["temperature"] as? Double, 0.3)
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.url?.absoluteString, "https://example.test/v1/chat/completions")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
                XCTAssertEqual(json["stream"] as? Bool, true)
            }
        }
    }

    @MainActor
    func testCustomReasoningIsNotSilentlyRemovedOnError() async throws {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = Preferences(defaults: defaults)
        prefs.baseURL = "https://example.test/reject"
        prefs.model = "test"
        prefs.reasoningEffort = "low"
        prefs.customInferenceParameters = "{\"reasoning_effort\":\"high\"}"
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [ParameterProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }
        do {
            for try await _ in OpenAICompatibleClient(session: session).streamCompletion(
                request: .init(model: "test", messages: [], stream: true), configuration: prefs.inferenceConfiguration(apiKey: "")) {}
            XCTFail("Explicit overrides should report the provider error")
        } catch let error as KKError {
            guard case .server(status: 400, message: _) = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertTrue(prefs.reasoningAttempts.isEmpty, "Custom overrides must not disable the picker setting")
    }

    func testErrorOnAnEstablishedEndpointDoesNotRetry() async throws {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [ParameterProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }
        var config = APIConfiguration(baseURL: "https://example.test/reject", apiKey: "", model: "test")
        config.reasoningEffort = "high"
        do {
            for try await _ in OpenAICompatibleClient(session: session).streamCompletion(
                request: .init(model: "test", messages: [], stream: true), configuration: config) {}
            XCTFail("Only a first attempt should retry without reasoning")
        } catch let error as KKError {
            guard case .server(status: 400, message: _) = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    @MainActor
    func testFirstRequestFallbackPersistsAndNewEndpointGetsTrial() async throws {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = Preferences(defaults: defaults)
        prefs.baseURL = "https://example.test/reject"
        prefs.model = "test"
        prefs.reasoningEffort = "high"
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [ParameterProtocol.self]
        let session = URLSession(configuration: sessionConfig)
        defer { session.invalidateAndCancel() }
        let client = OpenAICompatibleClient(session: session)
        let config = prefs.inferenceConfiguration(apiKey: "")
        for _ in 0..<2 {
            var answer = ""
            for try await delta in client.streamCompletion(request: .init(model: "test", messages: [], stream: true), configuration: config) {
                if case .content(let text) = delta { answer += text }
            }
            XCTAssertEqual(answer, "ok")
            XCTAssertTrue(prefs.reasoningDisabled)
        }
        let reloaded = Preferences(defaults: defaults)
        XCTAssertTrue(reloaded.reasoningDisabled)
        reloaded.baseURL = "https://example.test/accept"
        let policy = await reloaded.inferenceConfiguration(apiKey: "").reasoningPolicy!()
        XCTAssertEqual(policy.effort, "high")
        XCTAssertTrue(policy.trial)
        let next = await reloaded.inferenceConfiguration(apiKey: "").reasoningPolicy!()
        XCTAssertFalse(next.trial)
        reloaded.baseURL = prefs.baseURL
        reloaded.retryReasoning()
        XCTAssertFalse(reloaded.reasoningDisabled)
        prefs.customInferenceParameters = "{\"temperature\":0.5}"
        XCTAssertEqual(Preferences(defaults: defaults).customInferenceParameters, prefs.customInferenceParameters)
        prefs.resetAdvanced()
        XCTAssertEqual(prefs.customInferenceParameters, "{}")
        XCTAssertEqual(prefs.reasoningEffort, "high")
    }
}
