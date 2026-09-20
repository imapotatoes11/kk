import XCTest
@testable import kk

final class SSEParserTests: XCTestCase {
    func testEmitsDataEventsAndDone() {
        var parser = SSEParser()
        var output: [String] = []
        let lines = [
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}",
            "",
            "data: {\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}",
            "",
            ": keepalive",
            "data: [DONE]",
            ""
        ]

        for line in lines { output.append(contentsOf: parser.consume(line: line)) }

        XCTAssertEqual(output, [
            "{\"choices\":[{\"delta\":{\"content\":\"Hel\"}}]}",
            "{\"choices\":[{\"delta\":{\"content\":\"lo\"}}]}",
            "[DONE]"
        ])
    }

    func testFinishesAnEventWithoutTrailingBlankLine() {
        var parser = SSEParser()
        _ = parser.consume(line: "data: hello")
        XCTAssertEqual(parser.finish(), ["hello"])
    }
}
