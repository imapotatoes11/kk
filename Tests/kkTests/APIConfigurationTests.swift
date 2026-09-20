import XCTest
@testable import kk

final class APIConfigurationTests: XCTestCase {
    func testNormalizesBaseURL() throws {
        let first = APIConfiguration(baseURL: "https://api.openai.com/v1", apiKey: "", model: "model")
        let second = APIConfiguration(baseURL: "https://api.openai.com/v1/", apiKey: "", model: "model")

        XCTAssertEqual(first.endpointURL?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(second.endpointURL?.absoluteString, "https://api.openai.com/v1/chat/completions")
    }

    func testDoesNotDuplicateCompletionPath() {
        let configuration = APIConfiguration(
            baseURL: "https://api.openai.com/v1/chat/completions",
            apiKey: "",
            model: "model"
        )
        XCTAssertEqual(configuration.endpointURL?.absoluteString, "https://api.openai.com/v1/chat/completions")
    }

    func testAllowsEmptyAPIKeyAndRejectsInvalidURLOrModel() {
        XCTAssertNoThrow(try APIConfiguration(baseURL: "http://localhost:11434/v1", apiKey: "", model: "vision").validated())
        XCTAssertThrowsError(try APIConfiguration(baseURL: "file:///tmp", apiKey: "", model: "vision").validated())
        XCTAssertThrowsError(try APIConfiguration(baseURL: "https://example.com", apiKey: "", model: " ").validated())
    }
}
