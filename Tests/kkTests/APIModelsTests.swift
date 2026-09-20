import XCTest
@testable import kk

final class APIModelsTests: XCTestCase {
    func testMultimodalMessageHasOneJPEGImagePart() throws {
        let request = ChatCompletionRequest(
            model: "vision",
            messages: [
                APIMessage(role: "system", content: .text("system")),
                APIMessage(role: "user", content: .parts([
                    .text("why?"),
                    .imageURL("data:image/jpeg;base64,abc")
                ]))
            ],
            stream: true
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try XCTUnwrap(object["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.filter { $0["type"] as? String == "image_url" }.count, 1)
        XCTAssertEqual((parts[1]["image_url"] as? [String: String])?["url"], "data:image/jpeg;base64,abc")
    }
}
