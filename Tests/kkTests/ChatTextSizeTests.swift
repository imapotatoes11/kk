import AppKit
import SwiftMath
import SwiftUI
import XCTest
@testable import kk

final class ChatTextSizeTests: XCTestCase {
    @MainActor
    func testSliderSizesPersistAndLegacySelectionsMigrate() throws {
        let suite = "kk-chat-text-size-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(Preferences(defaults: defaults).answerTextSize.points, 14)
        for (legacy, points) in [("small", 13), ("standard", 14), ("large", 16)] {
            defaults.set(legacy, forKey: "answerTextSize")
            let preferences = Preferences(defaults: defaults)
            XCTAssertEqual(preferences.answerTextSize.points, CGFloat(points))
            preferences.answerTextSize = AnswerTextSize(points: 21)
            XCTAssertEqual(Preferences(defaults: defaults).answerTextSize.points, 21)
            preferences.answerTextSize = .standard
            XCTAssertEqual(Preferences(defaults: defaults).answerTextSize.points, 14)
        }
        defaults.set("invalid", forKey: "answerTextSize")
        XCTAssertEqual(Preferences(defaults: defaults).answerTextSize, .standard)
        XCTAssertEqual(AnswerTextSize(points: .nan), .standard)
        XCTAssertEqual(AnswerTextSize(points: -100).points, 12)
        XCTAssertEqual(AnswerTextSize(points: 100).points, 24)
    }

    @MainActor
    func testConversationSizesUpdateWithoutChangingComposerOrControls() async throws {
        _ = NSApplication.shared
        let suite = "kk-chat-font-render-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.baseURL = "https://fixture.invalid/v1"
        preferences.annotationsEnabled = false
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChatFontResponse.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let chat = ChatController(preferences: preferences, keychain: TestKeychain(),
            captureService: ScreenCaptureService(permissionCheck: { false }),
            apiClient: OpenAICompatibleClient(session: session))
        let panelController = PanelController(preferences: preferences)
        panelController.show(rootView: AnyView(PanelRootView(chat: chat, preferences: preferences,
            panelController: panelController, onOpenSettings: {}, onDismiss: {})), on: try XCTUnwrap(NSScreen.main))
        defer { chat.reset(); panelController.hide() }
        let panel = try XCTUnwrap(panelController.panel)
        let host = try XCTUnwrap(panel.contentView)
        chat.prompt = "Explain $x=2$."
        chat.submit()
        for _ in 0..<100 {
            if !chat.isStreaming { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(chat.messages.count, 2)
        chat.prompt = "This draft stays the same size."
        for appearance in [AppAppearance.light, .dark] {
            preferences.appearance = appearance
            var originalEditorHeight: CGFloat?
            for size in [14, 24, 12, 14] {
                preferences.answerTextSize = AnswerTextSize(points: CGFloat(size))
                try await Task.sleep(for: .milliseconds(800))
                host.layoutSubtreeIfNeeded()
                let labels = descendants(host).compactMap { $0 as? MTMathUILabel }
                let userMath = try XCTUnwrap(labels.first { $0.latex == "x=2" })
                let answerMath = try XCTUnwrap(labels.first { $0.latex == "y=3" })
                XCTAssertEqual(userMath.fontSize, CGFloat(size), "Sent questions must use the chat setting")
                XCTAssertEqual(answerMath.fontSize, CGFloat(size), "Answers must use the chat setting")
                let promptScroll = try XCTUnwrap(descendants(host).compactMap { $0 as? PromptScrollView }.first)
                let editor = try XCTUnwrap(promptScroll.documentView as? NSTextView)
                XCTAssertEqual(editor.font?.pointSize, 14)
                XCTAssertEqual(editor.string, "This draft stays the same size.")
                let editorHeight = promptScroll.frame.height
                if let originalEditorHeight { XCTAssertEqual(editorHeight, originalEditorHeight, accuracy: 1) }
                else { originalEditorHeight = editorHeight }
                XCTAssertLessThanOrEqual(panel.frame.height, UIConstants.panelMaxHeight)
                let editorColor = try XCTUnwrap(editor.textColor?.usingColorSpace(.deviceRGB))
                let mathColor = try XCTUnwrap(userMath.textColor?.usingColorSpace(.deviceRGB))
                if appearance == .dark {
                    XCTAssertGreaterThan(editorColor.redComponent, 0.9)
                    XCTAssertGreaterThan(mathColor.redComponent, 0.9)
                } else {
                    XCTAssertLessThan(editorColor.redComponent, 0.1)
                    XCTAssertLessThan(mathColor.redComponent, 0.1)
                }
                try snapshot(host, name: "chat-text-\(appearance.rawValue)-\(size)")
            }
        }
        XCTAssertGreaterThan(ConversationLayout.bubbleWidth(text: "A longer sent question", available: 600, fontSize: 24),
            ConversationLayout.bubbleWidth(text: "A longer sent question", available: 600, fontSize: 14))

        // Render the native settings control as well as the conversation at both size limits.
        let settings = NSHostingView(rootView: CustomizationView(preferences: preferences).frame(width: 640, height: 1000))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 1000), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = settings
        window.orderFront(nil)
        defer { window.close() }
        preferences.answerTextSize = AnswerTextSize(points: 21)
        try await Task.sleep(for: .milliseconds(300))
        try snapshot(settings, name: "chat-text-settings")
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    @MainActor private func snapshot(_ view: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["KK_RENDER_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }
}

private final class ChatFontResponse: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let answer = "## A short answer\n\nThe answer has **bold text**, a list, and math $y=3$.\n\n- First item\n- Second item"
        let event: [String: Any] = ["choices": [["delta": ["content": answer]]]]
        let data = try! JSONSerialization.data(withJSONObject: event)
        let body = "data: " + String(decoding: data, as: UTF8.self) + "\n\ndata: [DONE]\n\n"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
