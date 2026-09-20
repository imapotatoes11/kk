import XCTest
@testable import kk

final class ChatRequestBuilderTests: XCTestCase {
    func testNewRequestDoesNotSerializeInProgressAssistantPlaceholder() throws {
        let messages = ChatRequestBuilder.messages(
            for: [],
            firstImage: nil,
            appendingUserText: "why is this wrong?"
        )

        XCTAssertEqual(messages.map(\.role), ["system", "user"])
        guard case .text(let content) = messages[1].content else {
            return XCTFail("Expected a plain text first user message")
        }
        XCTAssertEqual(content, "why is this wrong?")
    }

    func testFollowUpRetainsTheImageOnlyOnTheFirstUserTurn() throws {
        let history = [
            ChatMessage(role: .user, content: "first"),
            ChatMessage(role: .assistant, content: "answer")
        ]
        let messages = ChatRequestBuilder.messages(
            for: history,
            firstImage: Data([1, 2, 3]),
            appendingUserText: "follow up"
        )

        XCTAssertEqual(messages.map(\.role), ["system", "user", "assistant", "user"])
        guard case .parts(let firstParts) = messages[1].content,
              case .text(let followUp) = messages[3].content else {
            return XCTFail("Expected multimodal first turn and text-only follow-up")
        }
        XCTAssertEqual(firstParts.count, 2)
        XCTAssertEqual(followUp, "follow up")
    }
}
