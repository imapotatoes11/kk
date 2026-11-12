import AppKit
import SwiftUI
import XCTest
@testable import kk

final class FollowUpTests: XCTestCase {
    @MainActor
    func testShortcutFocusesFollowupDuringAndAfterGenerationWithoutLosingState() async throws {
        _ = NSApplication.shared
        let prefs = preferences()
        prefs.annotationsEnabled = false
        let session = fixtureSession()
        defer { session.invalidateAndCancel() }
        let app = AppState(preferences: prefs, keychain: TestKeychain(), apiClient: OpenAICompatibleClient(session: session), captureService: ScreenCaptureService(permissionCheck: { false }))
        app.togglePanel()
        defer { app.dismissPanel() }
        let popup = try XCTUnwrap(app.panelController.panel)
        app.togglePanel()
        XCTAssertFalse(popup.isVisible, "The launcher still toggles before a question is sent")
        app.togglePanel()
        app.chat.removeScreen()
        app.chat.prompt = "first"
        app.chat.submit()
        app.chat.prompt = "next draft"
        app.togglePanel()
        XCTAssertTrue(app.panelController.isVisible)
        XCTAssertTrue(app.chat.hasSubmitted)
        XCTAssertEqual(app.chat.prompt, "next draft")
        try await waitUntil { !app.chat.isStreaming && popup.promptEditor != nil }
        let editor = try XCTUnwrap(popup.promptEditor)
        let messages = app.chat.messages
        let frame = popup.frame
        popup.makeFirstResponder(nil)
        app.togglePanel()
        XCTAssertTrue(popup.isKeyWindow)
        XCTAssertTrue(popup.firstResponder === editor)
        XCTAssertEqual(app.chat.messages, messages)
        XCTAssertEqual(app.chat.prompt, "next draft")
        XCTAssertEqual(popup.frame, frame)
    }

    func testEveryTurnKeepsItsOwnImageAndUnrelatedScreenGuidance() throws {
        let first = Data([1, 2]), second = Data([3, 4]), third = Data([5, 6])
        let history = [ChatMessage(role: .user, content: "first", screenData: first), ChatMessage(role: .assistant, content: "one"),
                       ChatMessage(role: .user, content: "second", screenData: second), ChatMessage(role: .assistant, content: "two")]
        let request = ChatRequestBuilder.messages(for: history, firstImage: nil, appendingUserText: "unrelated", appendingImage: third)
        let encoded = String(decoding: try JSONEncoder().encode(ChatCompletionRequest(model: "fixture", messages: request, stream: true)), as: UTF8.self)
        for data in [first, second, third] { XCTAssertTrue(encoded.contains(data.base64EncodedString())) }
        XCTAssertEqual(request.map(\.role), ["system", "user", "assistant", "user", "assistant", "user"])
        XCTAssertTrue(KKCopy.systemPrompt.contains("may or may not be relevant"))
        let noImage = ChatRequestBuilder.messages(for: history, firstImage: nil, appendingUserText: "text only")
        guard case .text(let text) = noImage.last?.content else { return XCTFail("Removed capture must not reuse a previous image") }
        XCTAssertEqual(text, "text only")
    }

    @MainActor
    func testFollowupCaptureAnnotationsRemovalAndRetryImage() async throws {
        _ = NSApplication.shared
        let prefs = preferences()
        let session = fixtureSession()
        defer { session.invalidateAndCancel() }
        let first = Data([1, 2, 3]), second = Data([4, 5, 6])
        let image = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let snapshot = ScreenSnapshot(image: image, data: second)
        let chat = ChatController(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(permissionCheck: { true }), apiClient: OpenAICompatibleClient(session: session), initialScreenContext: .ready(first), capture: { _ in snapshot })
        let annotations = AnnotationController(preferences: prefs)
        let screen = try XCTUnwrap(NSScreen.main)
        var preparedTurns = 0
        chat.onSubmit = { annotations.end() }
        chat.onCaptureReady = { annotations.receiveCapture($0) }
        chat.onPrepareFollowUp = {
            preparedTurns += 1
            annotations.begin(on: screen)
            chat.beginCapture(for: screen)
        }
        defer { chat.reset(); annotations.end() }
        chat.prompt = "first"
        chat.submit()
        try await waitUntil { !chat.isStreaming && chat.currentPreviewData == second }
        XCTAssertEqual(chat.messages.first?.screenData, first)
        XCTAssertEqual(preparedTurns, 1)
        XCTAssertNotNil(annotations.canvasPanel)
        annotations.document.begin(at: CGPoint(x: 10, y: 10), tool: .ellipse, color: .red, lineWidth: 3)
        annotations.document.move(to: CGPoint(x: 60, y: 60)); annotations.document.finish()
        XCTAssertEqual(annotations.document.annotations.count, 1)
        var didPrepareAnnotations = false
        chat.prepareScreen = { data in
            didPrepareAnnotations = true
            return try await annotations.prepareImage(fallback: data)
        }
        chat.prompt = "second"
        chat.submit()
        try await waitUntil { !chat.isStreaming && chat.messages.filter { $0.role == .user }.count == 2 && chat.currentPreviewData == second }
        XCTAssertTrue(didPrepareAnnotations)
        let originalImage = try XCTUnwrap(chat.messages.filter { $0.role == .user }.last?.screenData)
        XCTAssertNotEqual(originalImage, second, "Marks must be composited into this turn's JPEG")
        XCTAssertTrue(chat.isMultiTurn)
        XCTAssertEqual(annotations.document.annotations.count, 0, "Previous marks must not leak into the next turn")
        chat.retry()
        try await waitUntil { !chat.isStreaming && chat.currentPreviewData == second }
        XCTAssertEqual(chat.messages.filter { $0.role == .user }.count, 2)
        XCTAssertEqual(chat.messages.filter { $0.role == .user }.last?.screenData, originalImage)
        XCTAssertEqual(preparedTurns, 3)
        chat.onRemoveScreen = { annotations.end(); return true }
        chat.removeScreen()
        XCTAssertNil(chat.currentPreviewData)
        chat.prompt = "third, without image"
        chat.submit()
        try await waitUntil { !chat.isStreaming && chat.messages.filter { $0.role == .user }.count == 3 }
        XCTAssertNil(chat.messages.filter { $0.role == .user }.last?.screenData)
    }

    @MainActor
    func testMultiTurnDismissalConfirmationCopyFailureAndTranscript() async throws {
        _ = NSApplication.shared
        let prefs = preferences()
        prefs.confirmDismissChat = true
        prefs.copyChatOnDismiss = true
        let clipboard = FixtureClipboard()
        let session = fixtureSession()
        defer { session.invalidateAndCancel() }
        let app = AppState(preferences: prefs, keychain: TestKeychain(), clipboard: clipboard, apiClient: OpenAICompatibleClient(session: session), captureService: ScreenCaptureService(permissionCheck: { false }))
        defer { app.chat.reset(); app.copyFeedback.hide() }
        for question in ["first", "second"] {
            app.chat.prompt = question; app.chat.submit()
            try await waitUntil { !app.chat.isStreaming }
        }
        var confirmations = 0
        app.confirmChatDismissal = { confirmations += 1; return false }
        app.dismissPanel()
        XCTAssertTrue(app.chat.hasSubmitted)
        XCTAssertEqual(confirmations, 1)
        XCTAssertNil(clipboard.text)
        app.confirmChatDismissal = { true }
        clipboard.succeeds = false
        app.dismissPanel()
        XCTAssertTrue(app.chat.hasSubmitted, "A clipboard failure must preserve the chat")
        clipboard.succeeds = true
        app.dismissPanel()
        XCTAssertFalse(app.chat.hasSubmitted)
        XCTAssertTrue(clipboard.text?.contains("## You\n\nfirst") == true)
        XCTAssertTrue(clipboard.text?.contains("## kk\n\nShort answer.") == true)
        XCTAssertFalse(clipboard.text?.contains("data:image") == true)
        app.chat.prompt = "one turn"; app.chat.submit()
        try await waitUntil { !app.chat.isStreaming }
        app.confirmChatDismissal = { XCTFail("One turn must not prompt"); return false }
        app.dismissPanel()
        XCTAssertFalse(app.chat.hasSubmitted)
    }

    @MainActor
    func testWidthsPersistenceDefaultsBoundsAndContentSizing() async throws {
        _ = NSApplication.shared
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.openingWidth, 680)
        prefs.popupSize = .compact
        XCTAssertEqual(prefs.openingWidth, 480)
        prefs.compactWidthLevel = 4; prefs.fullWidthLevel = 5
        prefs.copyChatOnDismiss = true; prefs.confirmDismissChat = true
        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.openingWidth, 600)
        XCTAssertEqual(restored.fullWidthLevel, 5)
        XCTAssertTrue(restored.copyChatOnDismiss && restored.confirmDismissChat)
        restored.resetCustomization()
        XCTAssertEqual(restored.openingWidth, 680)
        XCTAssertFalse(restored.copyChatOnDismiss || restored.confirmDismissChat)
        prefs.compactWidthLevel = BarWidths.compactDefault
        let controller = PanelController(preferences: prefs)
        controller.show(rootView: AnyView(Color.clear), on: try XCTUnwrap(NSScreen.main))
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.panel)
        controller.updateLayout(hasResponse: true, minimumHeight: 220, contentHeight: 250, preferredWidth: 480, streaming: true)
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(panel.frame.size, NSSize(width: 480, height: 250))
        for height in stride(from: 260.0, through: 620.0, by: 10) {
            controller.updateLayout(hasResponse: true, minimumHeight: 220, contentHeight: height, preferredWidth: 680, streaming: true)
            try await Task.sleep(for: .milliseconds(8))
        }
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertEqual(panel.frame.size, NSSize(width: 680, height: 620))
        controller.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification, object: panel))
        panel.setFrame(NSRect(x: panel.frame.minX, y: panel.frame.minY, width: 520, height: 300), display: false)
        controller.updateLayout(hasResponse: true, minimumHeight: 220, contentHeight: 600, preferredWidth: 680)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(panel.frame.size, NSSize(width: 520, height: 300))
        XCTAssertEqual(panel.minSize.width, 480)
        XCTAssertEqual(panel.maxSize, try XCTUnwrap(panel.screen).visibleFrame.size, "Manual resizing may use the screen, including the annotation strip")
        XCTAssertLessThan(ConversationLayout.bubbleWidth(text: "test", available: 600), 80)
        XCTAssertEqual(ConversationLayout.bubbleWidth(text: String(repeating: "long ", count: 100), available: 480), 440)
        XCTAssertEqual(ConversationLayout.height(content: 3000, chrome: 100, minimum: 220, streaming: true), 620)
    }

    @MainActor
    func testShortConversationFitsAndRendersWithUsableComposer() async throws {
        _ = NSApplication.shared
        let session = fixtureSession()
        defer { session.invalidateAndCancel() }
        for mode in PopupSize.allCases {
            for dark in [false, true] {
                let prefs = preferences()
                prefs.popupSize = mode
                prefs.appearance = dark ? .dark : .light
                let chat = ChatController(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(permissionCheck: { false }), apiClient: OpenAICompatibleClient(session: session))
                let controller = PanelController(preferences: prefs)
                controller.show(rootView: AnyView(PanelRootView(chat: chat, preferences: prefs, panelController: controller, onOpenSettings: {}, onDismiss: {})), on: try XCTUnwrap(NSScreen.main))
                defer { controller.hide(); chat.reset() }
                chat.prompt = "test"; chat.submit()
                try await waitUntil { !chat.isStreaming }
                try await Task.sleep(for: .milliseconds(950))
                let panel = try XCTUnwrap(controller.panel)
                let host = try XCTUnwrap(panel.contentView)
                host.layoutSubtreeIfNeeded()
                XCTAssertEqual(panel.frame.width, prefs.openingWidth)
                XCTAssertGreaterThanOrEqual(panel.frame.height, 220)
                XCTAssertLessThan(panel.frame.height, 320, "Short chats should not open at the 620-point maximum")
                func views(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(views) }
                let editor = try XCTUnwrap(views(host).compactMap { $0 as? PromptScrollView }.first)
                XCTAssertGreaterThanOrEqual(editor.frame.height, 24)
                try render(host, name: "followup-\(mode.rawValue)-\(dark ? "dark" : "light")")
            }
        }
        let prefs = preferences()
        let app = AppState(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(permissionCheck: { false }))
        let selection = SettingsSelection()
        selection.section = .general
        let host = NSHostingView(rootView: SettingsView(preferences: prefs, selection: selection).environmentObject(app))
        host.frame.size = NSSize(width: 640, height: 640)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        try render(host, name: "followup-customization")
        // Render the entire scrollable form too, so controls below the initial fold are reviewed.
        window.setContentSize(NSSize(width: 640, height: 1000))
        try await Task.sleep(for: .milliseconds(200))
        try render(host, name: "followup-customization-complete")
        selection.section = .about
        try await Task.sleep(for: .milliseconds(200))
        try render(host, name: "followup-about")
    }

    @MainActor
    private func render(_ view: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["KK_RENDER_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }

    @MainActor
    private func preferences() -> Preferences {
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.baseURL = "https://fixture.invalid/v1"
        prefs.onboardingComplete = true
        return prefs
    }
    private func fixtureSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FollowUpProtocol.self]
        return URLSession(configuration: config)
    }
    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition())
    }
}

@MainActor
private final class FixtureClipboard: ClipboardWriting {
    var text: String?
    var succeeds = true
    func write(_ text: String) -> Bool { if succeeds { self.text = text }; return succeeds }
}

private final class FollowUpProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = "data: {\"choices\":[{\"delta\":{\"content\":\"Short answer.\"}}]}\n\ndata: [DONE]\n\n"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
