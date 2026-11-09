import AppKit
import SwiftUI
import XCTest
@testable import kk

final class MermaidExtractorTests: XCTestCase {
    func testFindsClosedMermaidBlocksOnly() {
        let text = """
        Intro
        ```mermaid
        flowchart LR
          A --> B
        ```
        Middle
        ```python
        print("```mermaid")
        ```
        ~~~ mermaid
        sequenceDiagram
          A->>B: hi
        ~~~
        ```mermaid
        flowchart TD
          X --> Y
        """
        let blocks = MermaidExtractor.blocks(in: text)
        XCTAssertEqual(blocks.map(\.code), ["flowchart LR\n  A --> B\n", "sequenceDiagram\n  A->>B: hi\n"],
                       "Fences inside other code blocks and unclosed fences are ignored")
    }

    func testLongerFencesAndInfoStrings() {
        let text = "````Mermaid {theme=x}\ngraph TD\n```\nnot closed yet\n````\n"
        let blocks = MermaidExtractor.blocks(in: text)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].code, "graph TD\n```\nnot closed yet\n")
    }

    func testReplacingKeepsFenceAndListIndent() throws {
        let text = "1. Steps:\n   ```mermaid\n   flowchart LR\n     A --> B(\"x\n   ```\n2. Done\n"
        let blocks = MermaidExtractor.blocks(in: text)
        XCTAssertEqual(blocks.first?.code, "flowchart LR\n  A --> B(\"x\n")
        let updated = try XCTUnwrap(MermaidExtractor.replacing("flowchart LR\n  A --> B(\"x", with: "flowchart LR\n  A --> B[\"x\"]", in: text))
        XCTAssertEqual(updated, "1. Steps:\n   ```mermaid\n   flowchart LR\n     A --> B[\"x\"]\n   ```\n2. Done\n")
        XCTAssertNil(MermaidExtractor.replacing("missing", with: "x", in: text))
    }

    func testReplacingOnlyChangesTheFirstMatchingDiagram() throws {
        let block = "```mermaid\ngraph TD\nA-->\n```"
        let updated = try XCTUnwrap(MermaidExtractor.replacing("graph TD\nA-->", with: "graph TD\nA-->B", in: block + "\n\n" + block))
        XCTAssertEqual(MermaidExtractor.blocks(in: updated).map { MermaidExtractor.key($0.code) }, ["graph TD\nA-->B", "graph TD\nA-->"])
    }

    func testDiagramInRepairReply() {
        XCTAssertEqual(MermaidExtractor.diagram(inReply: "Here:\n```mermaid\ngraph TD\nA-->B\n```\nDone"), "graph TD\nA-->B")
        XCTAssertEqual(MermaidExtractor.diagram(inReply: "```\ngraph TD\nA-->B\n```"), "graph TD\nA-->B")
        XCTAssertEqual(MermaidExtractor.diagram(inReply: "  graph TD\nA-->B  "), "graph TD\nA-->B")
        XCTAssertNil(MermaidExtractor.diagram(inReply: "   "))
    }

    func testThemeColors() {
        XCTAssertEqual(MermaidTheme.mix("#FF0000", "#FFFFFF", 0.5), "#FF8080")
        let light = MermaidTheme(isDark: false, accent: NSColor(srgbRed: 0, green: 0.478, blue: 1, alpha: 1))
        XCTAssertEqual(light.accent, "#007AFF")
        XCTAssertEqual(light.variables["primaryColor"] as? String, MermaidTheme.mix("#007AFF", "#FFFFFF", 0.10))
        XCTAssertEqual(MermaidTheme(isDark: true, accent: nil).background, "#1E1E1E")
    }

    func testFitScalesDownButNeverUp() {
        XCTAssertEqual(MermaidBlockView.fit(CGSize(width: 200, height: 100), width: 600, height: 400), CGSize(width: 200, height: 100))
        XCTAssertEqual(MermaidBlockView.fit(CGSize(width: 1200, height: 300), width: 600, height: 400), CGSize(width: 600, height: 150))
        XCTAssertEqual(MermaidBlockView.fit(CGSize(width: 300, height: 1200), width: 600, height: 400), CGSize(width: 100, height: 400))
    }

    func testDiagramLabelsScaleWithChatText() {
        let natural = CGSize(width: 300, height: 800)
        // 18 pt chat text: labels at 16.2 pt, so the diagram grows 1.246× and isn't height-capped.
        let large = MermaidBlockView.layout(natural: natural, available: 900, textSize: 18)
        XCTAssertEqual(large.size, CGSize(width: 373, height: 996))
        XCTAssertFalse(large.scrolls)
        // A wide diagram shrinks to fit the width...
        let wide = MermaidBlockView.layout(natural: CGSize(width: 1000, height: 200), available: 900, textSize: 14)
        XCTAssertEqual(wide.size.width, 900)
        XCTAssertFalse(wide.scrolls)
        // ...but never below 10 pt labels; past that it scrolls.
        let huge = MermaidBlockView.layout(natural: CGSize(width: 3000, height: 200), available: 600, textSize: 14)
        XCTAssertEqual(huge.size.width, floor(3000 * 10 / 13))
        XCTAssertTrue(huge.scrolls)
        // Tiny chat text doesn't push labels below the chat size.
        XCTAssertEqual(MermaidBlockView.layout(natural: natural, available: 900, textSize: 10).size.width, floor(300 * 9 / 13))
    }

    func testSystemPromptGuidanceFollowsSetting() {
        XCTAssertTrue(KKCopy.systemPrompt(diagrams: true).contains("```mermaid"))
        XCTAssertFalse(KKCopy.systemPrompt(diagrams: false).contains("mermaid"))
        XCTAssertTrue(KKCopy.systemPrompt(diagrams: false).contains("may or may not be relevant"))
    }
}

final class MermaidRendererTests: XCTestCase {
    @MainActor
    func testBundledMermaidValidatesAndRenders() async throws {
        XCTAssertNotNil(MermaidRenderer.scriptURL, "mermaid.min.js must be bundled")
        let renderer = MermaidRenderer.shared
        let valid = "flowchart LR\n  A[\"Start\"] --> B{\"Ready?\"}\n  B -->|yes| C[\"Ship it\"]"
        let validation = await renderer.validate(valid)
        XCTAssertNil(validation)
        let result = await renderer.render(valid, theme: MermaidTheme(isDark: false, accent: nil))
        guard case .diagram(let svg, let size) = result else { return XCTFail("Expected a diagram, got \(result)") }
        XCTAssertTrue(svg.hasPrefix("<svg"))
        XCTAssertTrue(svg.contains("Ship it"))
        XCTAssertTrue(svg.contains("-apple-system"), "Uses the native font stack")
        XCTAssertGreaterThan(size.width, 100)
        XCTAssertGreaterThan(size.height, 10)

        let dark = await renderer.render(valid, theme: MermaidTheme(isDark: true, accent: nil))
        guard case .diagram(let darkSVG, _) = dark else { return XCTFail() }
        XCTAssertNotEqual(svg, darkSVG, "Light and dark themes render separately")

        let broken = "flowchart LR\n  A[\"Start\" --> B"
        let error = await renderer.validate(broken)
        XCTAssertNotNil(error)
        let failed = await renderer.render(broken, theme: MermaidTheme(isDark: false, accent: nil))
        guard case .failure = failed else { return XCTFail("Broken diagrams fail") }

        let sequence = await renderer.render("sequenceDiagram\n  participant U as User\n  U->>kk: Question\n  kk-->>U: Answer", theme: MermaidTheme(isDark: false, accent: nil))
        guard case .diagram = sequence else { return XCTFail("Sequence diagrams render: \(sequence)") }
    }
}

extension MermaidRendererTests {
    @MainActor
    func testMathInFlowchartAndSequenceLabelsRendersAsMathML() async throws {
        let theme = MermaidTheme(isDark: false, accent: nil)
        for code in ["flowchart LR\n  A[\"$$\\frac{1}{2}mv^2$$\"] --> B", "sequenceDiagram\n  A->>B: $$\\sum_{i=1}^n i$$"] {
            let result = await MermaidRenderer.shared.render(code, theme: theme)
            guard case .diagram(let svg, _) = result else { return XCTFail("Expected a diagram for \(code): \(result)") }
            XCTAssertTrue(svg.contains("<math"), "Math renders as MathML")
            XCTAssertFalse(svg.contains("$$"), "No raw delimiters remain")
        }
        let prompt = KKCopy.systemPrompt(diagrams: true)
        XCTAssertTrue(prompt.contains("$$\\frac{1}{2}mv^2$$"), "The model is shown the math syntax")
        XCTAssertTrue(prompt.contains("single dollar signs aren't rendered"))
        XCTAssertTrue(KKCopy.diagramRepairPrompt.contains("Keep any $$...$$ math"))
    }
}

final class DiagramRepairTests: XCTestCase {
    @MainActor
    private func makeChat() -> (ChatController, Preferences) {
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.baseURL = "https://fixture.invalid/v1"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DiagramProtocol.self]
        let chat = ChatController(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(permissionCheck: { false }),
                                  apiClient: OpenAICompatibleClient(session: URLSession(configuration: config)))
        chat.removeScreen()
        chat.validateDiagram = { code in code.contains("BROKEN") ? "Parse error on line 2: unexpected token" : nil }
        DiagramProtocol.reset()
        return (chat, prefs)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition())
    }

    private static let brokenAnswer = "Here:\n\n```mermaid\nflowchart LR\n  A --> BROKEN(\n```\n\nThat's it."

    @MainActor
    func testBrokenDiagramIsRepairedInPlace() async throws {
        let (chat, _) = makeChat()
        DiagramProtocol.answer = Self.brokenAnswer
        DiagramProtocol.repairReply = "```mermaid\nflowchart LR\n  A --> B[\"Fixed\"]\n```"
        chat.prompt = "draw it"
        chat.submit()
        try await waitUntil { chat.messages.last?.content.contains("Fixed") == true }
        XCTAssertEqual(chat.messages.last?.content, "Here:\n\n```mermaid\nflowchart LR\n  A --> B[\"Fixed\"]\n```\n\nThat's it.")
        XCTAssertEqual(DiagramProtocol.requests.count, 2, "One answer plus exactly one repair request")
        let repair = DiagramProtocol.requests[1]
        XCTAssertTrue(repair.contains("unexpected token"), "The parser error is sent")
        XCTAssertTrue(repair.contains("BROKEN("), "The broken diagram is sent")
        XCTAssertTrue(repair.contains("draw it"), "The question gives context")
        try await waitUntil { chat.diagramRepairs.statuses.isEmpty }
        XCTAssertTrue(DiagramProtocol.requests[0].contains("```mermaid"), "Diagram guidance is in the system prompt")
    }

    @MainActor
    func testFailedRepairMarksDiagramAndKeepsAnswer() async throws {
        let (chat, _) = makeChat()
        DiagramProtocol.answer = Self.brokenAnswer
        DiagramProtocol.repairReply = "```mermaid\nflowchart LR\n  A --> BROKEN((\n```"
        chat.prompt = "draw it"
        chat.submit()
        try await waitUntil { if case .failed = chat.diagramRepairs.status(for: "flowchart LR\n  A --> BROKEN(") { true } else { false } }
        XCTAssertEqual(chat.messages.last?.content, Self.brokenAnswer)
        XCTAssertEqual(DiagramProtocol.requests.count, 2, "Only one repair attempt")
    }

    @MainActor
    func testValidDiagramsAndDisabledSettingsSendNoRepair() async throws {
        let (chat, prefs) = makeChat()
        DiagramProtocol.answer = "```mermaid\nflowchart LR\n  A --> B\n```"
        chat.prompt = "one"
        chat.submit()
        try await waitUntil { !chat.isStreaming && chat.diagramRepairs.statuses.isEmpty }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(DiagramProtocol.requests.count, 1)

        prefs.repairDiagrams = false
        DiagramProtocol.answer = Self.brokenAnswer
        chat.prompt = "two"
        chat.submit()
        try await waitUntil { if case .failed = chat.diagramRepairs.status(for: "flowchart LR\n  A --> BROKEN(") { true } else { false } }
        XCTAssertEqual(DiagramProtocol.requests.count, 2, "Repair off: the error shows without another request")

        prefs.renderDiagrams = false
        chat.reset()
        chat.removeScreen()
        chat.prompt = "three"
        chat.submit()
        try await waitUntil { !chat.isStreaming }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(chat.diagramRepairs.statuses.isEmpty, "Drawing off: diagrams aren't checked")
        XCTAssertFalse(DiagramProtocol.requests.last?.contains("```mermaid") ?? true, "Drawing off: no diagram guidance")
    }

    @MainActor
    func testStopSkipsUnfinishedDiagram() async throws {
        let (chat, _) = makeChat()
        DiagramProtocol.answer = "```mermaid\nflowchart LR\n  A --> BROKEN("
        chat.prompt = "draw"
        chat.submit()
        chat.stop()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(chat.diagramRepairs.statuses.isEmpty)
        XCTAssertLessThanOrEqual(DiagramProtocol.requests.count, 1)
    }
}

final class MermaidRenderTests: XCTestCase {
    /// Renders diagrams in a conversation in light and dark. Set KK_RENDER_DIR to save PNGs.
    @MainActor
    func testDiagramsRenderInConversation() async throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.baseURL = "https://fixture.invalid/v1"
        prefs.onboardingComplete = true
        prefs.annotationsEnabled = false
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DiagramProtocol.self]
        DiagramProtocol.reset()
        DiagramProtocol.answer = """
        The request goes through three stages:

        ```mermaid
        flowchart LR
          Q["Question"] --> C{"Screen attached?"}
          C -->|yes| V["Vision model"]
          C -->|no| T["Text model"]
          V --> A["Answer"]
          T --> A
        ```

        And the exchange looks like this:

        ```mermaid
        sequenceDiagram
          participant U as You
          participant K as kk
          participant P as Provider
          U->>K: Ask with ⌘⌥K
          K->>P: Question + screen
          P-->>K: Streamed answer
          K-->>U: Rendered reply
        ```
        """
        let app = AppState(preferences: prefs, keychain: TestKeychain(), apiClient: OpenAICompatibleClient(session: URLSession(configuration: config)),
                           captureService: ScreenCaptureService(permissionCheck: { false }))
        app.togglePanel()
        defer { app.dismissPanel() }
        let panel = try XCTUnwrap(app.panelController.panel)
        app.chat.removeScreen()
        app.chat.prompt = "How does kk answer?"
        app.chat.submit()
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while (app.chat.isStreaming || !app.chat.diagramRepairs.statuses.isEmpty) && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        for appearance in [AppAppearance.light, .dark] {
            prefs.appearance = appearance
            panel.appearance = appearance.nsAppearance
            try await Task.sleep(for: .seconds(3))
            panel.contentView?.layoutSubtreeIfNeeded()
            try await render(panel, "diagram-\(appearance == .light ? "light" : "dark")")
        }
    }

    @MainActor
    private func render(_ panel: NSWindow, _ name: String) async throws {
        guard let directory = ProcessInfo.processInfo.environment["KK_RENDER_DIR"], let view = panel.contentView else { return }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
        // Web views draw out of process, so snapshot each diagram separately.
        func webViews(_ view: NSView) -> [PassiveWebView] { ((view as? PassiveWebView).map { [$0] } ?? []) + view.subviews.flatMap(webViews) }
        let diagrams = webViews(view)
        XCTAssertEqual(diagrams.count, 2, "Both diagrams are drawn")
        for (index, webView) in diagrams.enumerated() {
            let image = try await webView.takeSnapshot(configuration: nil)
            let rep = try XCTUnwrap(image.representations.first as? NSBitmapImageRep ?? NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name)-\(index + 1).png"))
        }
    }
}

private final class DiagramProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var answer = "Plain answer."
    nonisolated(unsafe) static var repairReply = ""
    nonisolated(unsafe) static var requests: [String] = []
    private static let lock = NSLock()

    static func reset() {
        lock.withLock { answer = "Plain answer."; repairReply = ""; requests = [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = Self.body(of: request)
        let reply: String = Self.lock.withLock {
            Self.requests.append(body)
            return body.contains("fails to parse") ? Self.repairReply : Self.answer
        }
        let chunk = try! JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": reply]]]])
        let stream = "data: \(String(decoding: chunk, as: UTF8.self))\n\ndata: [DONE]\n\n"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stream.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func body(of request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

final class NarrowChatTests: XCTestCase {
    /// At the minimum width, nothing may hold the content wider than the window, which would
    /// clip the header and the question field on both sides.
    @MainActor
    func testConversationFitsMinimumWidth() async throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.baseURL = "https://fixture.invalid/v1"
        prefs.onboardingComplete = true
        prefs.annotationsEnabled = false
        prefs.placeInBlankSpace = true
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NarrowProtocol.self]
        let app = AppState(preferences: prefs, keychain: TestKeychain(), apiClient: OpenAICompatibleClient(session: URLSession(configuration: config)),
                           captureService: ScreenCaptureService(permissionCheck: { false }))
        app.togglePanel()
        defer { app.dismissPanel() }
        let panel = try XCTUnwrap(app.panelController.panel)
        app.chat.removeScreen()
        app.chat.prompt = String(repeating: "A long question that should wrap inside its bubble. ", count: 4)
        app.chat.submit()
        let deadline = ContinuousClock.now.advanced(by: .seconds(15))
        while (app.chat.isStreaming || !app.chat.diagramRepairs.statuses.isEmpty) && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        try await Task.sleep(for: .seconds(2))

        let size = app.panelController.windowWillResize(panel, to: NSSize(width: 200, height: 500))
        XCTAssertEqual(size.width, PanelController.minimumWidth)
        // Resize the way a drag does, so layout treats it as the user's choice.
        app.panelController.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification, object: panel))
        panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: true)
        try await Task.sleep(for: .seconds(1))
        XCTAssertEqual(panel.frame.width, PanelController.minimumWidth, accuracy: 0.5)
        let host = try XCTUnwrap(panel.contentView)
        host.layoutSubtreeIfNeeded()
        func all(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(all) }
        let diagrams = all(host).compactMap { $0 as? PassiveWebView }
        XCTAssertFalse(diagrams.isEmpty, "The diagram is drawn")
        // A diagram too wide for readable labels scrolls inside its card; check what's visible.
        let visible: [NSView] = diagrams.map { $0.enclosingScrollView ?? $0 }
        for view in visible + [panel.promptEditor].compactMap({ $0 }) {
            let frame = view.convert(view.bounds, to: host)
            XCTAssertGreaterThanOrEqual(frame.minX, -0.5, "\(type(of: view)) is clipped on the left")
            XCTAssertLessThanOrEqual(frame.maxX, host.bounds.maxX + 0.5, "\(type(of: view)) is clipped on the right")
        }
        if let directory = ProcessInfo.processInfo.environment["KK_RENDER_DIR"] {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("narrow-chat.png"))
        }
        // Scrolling the clipped diagram sideways retires the persistent hint.
        let scroller = try XCTUnwrap(diagrams.first?.enclosingScrollView)
        scroller.contentView.scroll(to: NSPoint(x: 40, y: scroller.contentView.bounds.minY))
        scroller.reflectScrolledClipView(scroller.contentView)
        try await Task.sleep(for: .milliseconds(600))
        host.layoutSubtreeIfNeeded()
        if let directory = ProcessInfo.processInfo.environment["KK_RENDER_DIR"] {
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("narrow-chat-scrolled.png"))
        }
    }
}

private final class NarrowProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let answer = "Here:\n\n```mermaid\nflowchart TD\n  A[\"Start: a fairly wide first step label\"] --> B{\"Resize step below minimum?\"}\n  B -->|Yes| C[\"Block resize - stop at minimum width\"]\n  B -->|No| D[\"Allow resize to continue\"]\n```"
        let chunk = try! JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": answer]]]])
        let body = "data: \(String(decoding: chunk, as: UTF8.self))\n\ndata: [DONE]\n\n"
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
