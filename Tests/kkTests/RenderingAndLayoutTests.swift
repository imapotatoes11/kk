import AppKit
import SwiftMath
import SwiftUI
import XCTest
@testable import kk

final class RenderingAndLayoutTests: XCTestCase {
    @MainActor
    func testFullPopupWithWrappedPromptAndLongSyntheticAnswer() async throws {
        _ = NSApplication.shared
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.popupSize = .compact
        preferences.baseURL = "https://fixture.invalid/v1"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PolishResponseProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let chat = ChatController(preferences: preferences, keychain: TestKeychain(), captureService: ScreenCaptureService(), apiClient: OpenAICompatibleClient(session: session))
        let controller = PanelController(preferences: preferences)
        let root = PanelRootView(chat: chat, preferences: preferences, panelController: controller, onOpenSettings: {}, onDismiss: {})
        controller.show(rootView: AnyView(root), on: try XCTUnwrap(NSScreen.main))
        defer { controller.hide(); chat.reset() }
        let panel = try XCTUnwrap(controller.panel)
        let host = try XCTUnwrap(panel.contentView)
        panel.appearance = NSAppearance(named: .aqua)
        try await settle(host)
        let initialHeight = panel.frame.height
        try snapshot(host, name: "popup-empty")
        chat.prompt = String(repeating: "Please explain this equation and show the working steps. ", count: 8)
        try await settle(host)
        XCTAssertGreaterThan(panel.frame.height, initialHeight)
        try snapshot(host, name: "popup-wrapped-prompt")
        chat.submit()
        try await settle(host)
        try await settle(host)
        XCTAssertEqual(chat.messages.last?.content, PolishResponseProtocol.answer)
        XCTAssertFalse(chat.isStreaming)
        XCTAssertLessThanOrEqual(panel.frame.height, UIConstants.panelMaxHeight)
        XCTAssertGreaterThanOrEqual(panel.frame.height, panel.minSize.height)
        let conversation = try XCTUnwrap(descendants(of: host).compactMap { $0 as? NSScrollView }.first { !($0 is PromptScrollView) })
        XCTAssertGreaterThan(conversation.contentView.bounds.origin.y, 100, "A growing answer must follow to its bottom after window layout")
        try snapshot(host, name: "popup-long-answer")
        controller.annotationLayerActive = true
        controller.expandToFit()
        try await settle(host)
        try await settle(host)
        let safe = PanelPositioning.automaticBounds(in: try XCTUnwrap(NSScreen.main).visibleFrame, palette: preferences.palettePosition)
        XCTAssertLessThanOrEqual(panel.frame.maxY, safe.maxY + 1)
        XCTAssertGreaterThanOrEqual(panel.frame.minY, safe.minY - 1)
        let documentHeight = try XCTUnwrap(conversation.documentView).frame.height
        XCTAssertTrue(documentHeight <= conversation.contentSize.height + 2 || panel.frame.height >= safe.height - 2,
                      "Expand must remove vertical scrolling unless the display is full")
        // The manual width must also reflow the composer and protect its minimum height.
        panel.setContentSize(NSSize(width: 480, height: 500))
        controller.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification, object: panel))
        chat.prompt = String(repeating: "A wrapped follow-up. ", count: 40)
        try await settle(host)
        XCTAssertEqual(panel.frame.width, 480)
        XCTAssertGreaterThanOrEqual(panel.frame.height, panel.minSize.height)
        try snapshot(host, name: "popup-narrow")
    }

    @MainActor
    func testScrollToLatestAppearsWhenScrolledUpAndReturnsToBottom() async throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.baseURL = "https://fixture.invalid/v1"
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PolishResponseProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let chat = ChatController(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(), apiClient: OpenAICompatibleClient(session: session))
        chat.prompt = "Explain this"
        chat.submit()
        defer { chat.reset() }
        let host = NSHostingView(rootView: ConversationView(chat: chat, preferences: prefs, onCopyAnswer: { _ in }).frame(width: 500, height: 320).background(Color(nsColor: .windowBackgroundColor)))
        let window = mount(host)
        defer { window.close() }
        try await settle(host)
        try await settle(host)
        let scroll = try XCTUnwrap(descendants(of: host).compactMap { $0 as? NSScrollView }.first)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(document.bounds.height, scroll.contentSize.height)

        let wheel = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
            wheelCount: 1, wheel1: 2000, wheel2: 0, wheel3: 0))
        wheel.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        wheel.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(CGScrollPhase.began.rawValue))
        for index in 0..<2 {
            if index > 0 { wheel.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(CGScrollPhase.changed.rawValue)) }
            let event = try XCTUnwrap(NSEvent(cgEvent: wheel))
            scroll.scrollWheel(with: event)
            try await Task.sleep(for: .milliseconds(30))
        }
        wheel.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(CGScrollPhase.ended.rawValue))
        wheel.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
        wheel.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
        scroll.scrollWheel(with: try XCTUnwrap(NSEvent(cgEvent: wheel)))
        try await settle(host)
        XCTAssertLessThan(scroll.contentView.bounds.minY, 100, "The wheel event must actually scroll back to the start")
        try snapshot(host, name: "chat-scrolled-up")
        // SwiftUI plain buttons don't necessarily expose an NSButton descendant.
        // Click the rendered control through the window's ordinary event path.
        let local = NSPoint(x: host.bounds.midX, y: host.isFlipped ? host.bounds.maxY - 25 : host.bounds.minY + 25)
        let point = host.convert(local, to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
        // The jump animates (and may retry after AppKit's bounce), so wait for it to arrive.
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while scroll.contentView.bounds.maxY < document.bounds.height - UIConstants.scrollFollowThreshold && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await settle(host)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 100)
        XCTAssertGreaterThanOrEqual(scroll.contentView.bounds.maxY, document.bounds.height - UIConstants.scrollFollowThreshold)
        try snapshot(host, name: "chat-returned-to-latest")
    }

    @MainActor
    func testCompletedMarkdownAndLatexRenderOnMountAndRemount() async throws {
        _ = NSApplication.shared
        let fixture = #"""
        ## Markdown and math

        **Bold**, *italic*, `inline code`, and [a link](https://example.com).

        - First item
        - Second item with inline math $E=mc^2$ and \(a^2+b^2=c^2\).

        > A block quote should wrap naturally without losing its last line.

        ```swift
        let greeting = "Hello, world"
        print(greeting)
        ```

        | Item | Value |
        | --- | --- |
        | Alpha | 42 |
        | Beta | 137 |

        $$\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}$$

        \[
        \frac{-b \pm \sqrt{b^2-4ac}}{2a}
        \]

        The final line stays visible.
        """#
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let host = NSHostingView(rootView: ResponseView(markdown: fixture, isStreaming: false).padding(20).frame(width: 620).background(Color(nsColor: .windowBackgroundColor)))
            let window = mount(host, appearance: appearance)
            defer { window.close() }
            try await settle(host)
            let labels = descendants(of: host).compactMap { $0 as? MTMathUILabel }
            XCTAssertGreaterThanOrEqual(labels.count, 2, "Both display math delimiter styles must produce native math views")
            for label in labels {
                XCTAssertNil(label.error, "LaTeX parse error: \(label.latex)")
                XCTAssertNotNil(label.displayList)
                XCTAssertGreaterThan(label.bounds.height, 10)
            }
            XCTAssertGreaterThan(host.fittingSize.height, 300)
            try snapshot(host, name: appearance == .aqua ? "response-light" : "response-dark")

            // Completed rows are recreated when scrolling or reopening a view.
            host.rootView = ResponseView(markdown: fixture, isStreaming: false).padding(20).frame(width: 620).background(Color(nsColor: .windowBackgroundColor))
            try await settle(host)
            XCTAssertGreaterThanOrEqual(descendants(of: host).compactMap { $0 as? MTMathUILabel }.count, 2)
        }
    }

    @MainActor
    func testStreamingAnswerFinalizesAndPreviousAnswerSurvivesFollowup() async throws {
        _ = NSApplication.shared
        let state = ResponseFixture()
        let host = NSHostingView(rootView: StreamingFixtureView(state: state).padding(20).frame(width: 620))
        let window = mount(host)
        defer { window.close() }
        try await settle(host)
        state.text += "\n\n$$\\frac{1}{2} + \\frac{1}{2} = 1$$"
        try await settle(host)
        XCTAssertFalse(descendants(of: host).compactMap { $0 as? MTMathUILabel }.isEmpty)
        state.streaming = false
        try await settle(host)
        XCTAssertEqual(descendants(of: host).compactMap { $0 as? MTMathUILabel }.first?.latex, "\\frac{1}{2} + \\frac{1}{2} = 1")
        state.followup = true
        try await settle(host)
        XCTAssertFalse(descendants(of: host).compactMap { $0 as? MTMathUILabel }.isEmpty, "The completed answer must survive a follow-up")
    }

    @MainActor
    func testEditorMeasuresWrappedTextAndScrollsLongPrompts() async throws {
        _ = NSApplication.shared
        let longText = String(repeating: "This question should wrap at the editor width. ", count: 12)
        var measuredHeight: CGFloat = 0
        let host = NSHostingView(rootView: PromptEditor(text: .constant(longText), isDisabled: false, onSubmit: {}, onHeightChange: { measuredHeight = $0 }).frame(width: 280, height: 100))
        let window = mount(host)
        defer { window.close() }
        try await settle(host)
        let scrollView = try XCTUnwrap(descendants(of: host).compactMap { $0 as? PromptScrollView }.first)
        let editor = try XCTUnwrap(scrollView.documentView as? NSTextView)
        XCTAssertGreaterThan(measuredHeight, 100, "Wrapping must contribute to the measured prompt height without explicit newlines")
        XCTAssertGreaterThan(editor.frame.height, scrollView.contentSize.height)
        XCTAssertLessThanOrEqual(editor.textContainer!.containerSize.width, scrollView.contentSize.width)
        XCTAssertFalse(scrollView.hasHorizontalScroller)
    }

    @MainActor
    func testPanelKeepsManualSizeAndCurrentDisplayWhileGrowing() throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        let controller = PanelController(preferences: Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        controller.show(rootView: AnyView(Color.clear), on: screen)
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertTrue(panel.styleMask.contains(.resizable))
        XCTAssertTrue(panel.isMovable)
        let origin = NSPoint(x: screen.visibleFrame.midX - 240, y: screen.visibleFrame.midY - 100)
        panel.setFrame(NSRect(origin: origin, size: NSSize(width: 480, height: 280)), display: false)
        let top = panel.frame.maxY
        controller.resize(height: 400, animated: false)
        XCTAssertEqual(panel.frame.width, 480)
        XCTAssertEqual(panel.frame.maxY, top, accuracy: 1)
        controller.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification, object: panel))
        let frame = panel.frame
        controller.resize(height: 600, animated: false)
        XCTAssertEqual(panel.frame, frame, "Automatic growth must respect manual resizing")
    }

    @MainActor
    private func mount<Content: View>(_ host: NSHostingView<Content>, appearance: NSAppearance.Name = .aqua) -> NSWindow {
        host.appearance = NSAppearance(named: appearance)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.center()
        window.orderFront(nil)
        return window
    }

    @MainActor
    private func settle(_ view: NSView) async throws {
        try await Task.sleep(for: .milliseconds(200))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
    }

    @MainActor
    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    @MainActor
    private func snapshot(_ view: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["KK_RENDER_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }
}

private final class PolishResponseProtocol: URLProtocol, @unchecked Sendable {
    static let answer = #"""
    ## A worked example

    Start with **the quadratic formula**, using inline math $a=1$, $b=-3$, and $c=2$.

    $$x = \frac{-b \pm \sqrt{b^2-4ac}}{2a}$$

    1. Substitute the coefficients.
    2. Simplify the discriminant.
    3. The solutions are $x=1$ and $x=2$.

    ```swift
    let roots = [1, 2]
    print(roots)
    ```

    | Root | Verification |
    | --- | --- |
    | 1 | 1 − 3 + 2 = 0 |
    | 2 | 4 − 6 + 2 = 0 |

    """# + String(repeating: "\n\nA longer explanation wraps within the popup. You can scroll back to review earlier steps without the answer pulling you to the bottom.", count: 8) + "\n\n**End of answer.**"

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let event: [String: Any] = ["choices": [["delta": ["content": Self.answer]]]]
        let data = try! JSONSerialization.data(withJSONObject: event)
        let body = "data: " + String(decoding: data, as: UTF8.self) + "\n\ndata: [DONE]\n\n"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private final class ResponseFixture: ObservableObject {
    @Published var text = "## Streaming answer\n\nThis is **formatted** text."
    @Published var streaming = true
    @Published var followup = false
}

private struct StreamingFixtureView: View {
    @ObservedObject var state: ResponseFixture
    var body: some View {
        VStack(alignment: .leading) {
            ResponseView(markdown: state.text, isStreaming: state.streaming)
            if state.followup { ResponseView(markdown: "A follow-up is streaming…", isStreaming: true) }
        }
    }
}
