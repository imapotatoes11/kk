import AppKit
import SwiftUI
import XCTest
@testable import kk

final class LauncherThinkingCopyTests: XCTestCase {
    @MainActor
    func testCommandCDispatchesThroughPopupKeyEquivalent() throws {
        _ = NSApplication.shared
        let panel = KKPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 56), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        var invoked = false
        panel.onCopyShortcut = { invoked = true; return true }
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: panel.windowNumber, context: nil, characters: "c", charactersIgnoringModifiers: "c", isARepeat: false, keyCode: 8))
        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        XCTAssertTrue(invoked)
    }

    @MainActor
    func testOpeningLayoutsHaveNoReservedEmptySpace() async throws {
        _ = NSApplication.shared
        for mode in PopupSize.allCases {
            for needsAccess in [false, true] {
                let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
                prefs.popupSize = mode
                let chat = ChatController(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(), apiClient: OpenAICompatibleClient(), initialScreenContext: needsAccess ? .permissionRequired : .disabled)
                let controller = PanelController(preferences: prefs)
                let root = PanelRootView(chat: chat, preferences: prefs, panelController: controller, onOpenSettings: {}, onDismiss: {})
                controller.show(rootView: AnyView(root), on: try XCTUnwrap(NSScreen.main))
                defer { controller.hide() }
                try await Task.sleep(for: .milliseconds(400))
                let panel = try XCTUnwrap(controller.panel)
                XCTAssertEqual(panel.frame.width, mode == .compact ? 480 : 680)
                XCTAssertLessThan(panel.frame.height, needsAccess ? 240 : (mode == .compact ? 80 : 150))
                if needsAccess { XCTAssertGreaterThan(panel.frame.height, mode == .compact ? 90 : 150) }
                try snapshot(try XCTUnwrap(panel.contentView), name: "opening-\(mode.rawValue)-\(needsAccess ? "permission" : "clean")")
            }
        }
    }

    @MainActor
    func testReasoningSeparatesFromAnswerAndDoesNotEnterFollowup() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReasoningProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.baseURL = "https://fixture.invalid/v1"
        let chat = ChatController(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(), apiClient: OpenAICompatibleClient(session: session))
        chat.prompt = "A fixture question"
        chat.submit()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertTrue(chat.isStreaming)
        XCTAssertEqual(chat.messages.last?.reasoning, "Provider reasoning summary.")
        XCTAssertEqual(chat.messages.last?.content, "")
        XCTAssertNotNil(chat.messages.last?.reasoningStartedAt)
        prefs.showThinking = true
        let host = NSHostingView(rootView: AssistantMessageView(message: try XCTUnwrap(chat.messages.last), isStreaming: true, preferences: prefs, onCopy: {}).padding(16).frame(width: 600).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(350))
        try snapshot(host, name: "thinking-pending")
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertFalse(chat.isStreaming)
        let answer = try XCTUnwrap(chat.messages.last)
        XCTAssertEqual(answer.content, "The final answer.")
        XCTAssertNotNil(answer.reasoningEndedAt)
        XCTAssertGreaterThan(answer.thinkingDuration(), 0.5)
        let followup = ChatRequestBuilder.messages(for: chat.messages, firstImage: nil, appendingUserText: "Next")
        let data = try JSONEncoder().encode(ChatCompletionRequest(model: "fixture", messages: followup, stream: true))
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("Provider reasoning summary"))
    }

    func testReasoningOnlyAndTruncatedStreamsFailWithoutMixingText() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReasoningProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        for variant in ["reasoning-only", "truncated-reasoning", "nonstream"] {
            var events: [CompletionDelta] = []
            do {
                let request = ChatCompletionRequest(model: "fixture", messages: [], stream: true)
                let config = APIConfiguration(baseURL: "https://fixture.invalid/" + variant, apiKey: "", model: "fixture")
                for try await delta in OpenAICompatibleClient(session: session).streamCompletion(request: request, configuration: config) { events.append(delta) }
                if variant != "nonstream" { XCTFail("Reasoning without an answer must fail") }
            } catch let error as KKError {
                guard case .streamFailed = error else { return XCTFail("Unexpected error: \(error)") }
                if variant == "nonstream" { XCTFail("A complete non-stream response should succeed") }
            }
            XCTAssertEqual(events.first, .reasoning("Provider reasoning summary."))
            if variant == "nonstream" { XCTAssertEqual(events.last, .content("The final answer.")) }
            else { XCTAssertEqual(events.count, 1) }
        }
    }

    @MainActor
    func testStoppingThinkingFreezesDurationAndDiscardsLateAnswer() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReasoningProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.baseURL = "https://fixture.invalid/v1"
        let chat = ChatController(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(), apiClient: OpenAICompatibleClient(session: session))
        chat.prompt = "Fixture"
        chat.submit()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(chat.messages.last?.reasoning.isEmpty ?? true)
        chat.stop()
        let ended = try XCTUnwrap(chat.messages.last?.reasoningEndedAt)
        try await Task.sleep(for: .milliseconds(800))
        XCTAssertFalse(chat.isStreaming)
        XCTAssertEqual(chat.messages.last?.content, "")
        XCTAssertEqual(chat.messages.last?.reasoningEndedAt, ended)
    }

    func testReasoningAliasesSummariesAndEncryptedBlocks() throws {
        let decoder = JSONDecoder()
        let aliases = try decoder.decode(AssistantDelta.self, from: Data(#"{"reasoning_content":"once","reasoning":"once","reasoning_details":[{"type":"reasoning.text","text":"once"}],"content":"answer"}"#.utf8))
        XCTAssertEqual(aliases.reasoning, "once")
        let summary = try decoder.decode(AssistantDelta.self, from: Data(#"{"reasoning_details":[{"type":"reasoning.summary","summary":"Summary"},{"type":"reasoning.encrypted","text":"secret ciphertext"}],"content":"answer"}"#.utf8))
        XCTAssertEqual(summary.reasoning, "Summary")
        XCTAssertEqual(summary.content, "answer")
        let unusual = try decoder.decode(AssistantDelta.self, from: Data(#"{"reasoning":{"unusual":true},"content":"still readable"}"#.utf8))
        XCTAssertEqual(unusual.content, "still readable")
        XCTAssertNil(unusual.reasoning)
        XCTAssertEqual(ThinkingDuration.label(0.2), "<1 sec")
        XCTAssertEqual(ThinkingDuration.label(61), "1 min 1 sec")
        XCTAssertEqual(ThinkingDuration.label(120), "2 min")
    }

    @MainActor
    func testCopyFeedbackAndCopyCloseUseSuccessfulClipboardWrite() async throws {
        _ = NSApplication.shared
        let pasteboard = NSPasteboard(name: .init("kk-test-" + UUID().uuidString))
        defer { pasteboard.releaseGlobally() }
        let feedback = CopyFeedbackController(clipboard: SystemClipboardWriter(pasteboard: pasteboard))
        XCTAssertTrue(feedback.copy("An answer", near: nil))
        XCTAssertEqual(pasteboard.string(forType: .string), "An answer")
        XCTAssertTrue(feedback.panel?.isVisible == true)
        XCTAssertFalse(feedback.copy("", near: nil))
        XCTAssertEqual(pasteboard.string(forType: .string), "An answer", "An empty copy must not clear the clipboard")
        feedback.hide()
        let failure = CopyFeedbackController(clipboard: FailedClipboard())
        XCTAssertFalse(failure.copy("An answer", near: nil))
        XCTAssertTrue(failure.panel?.isVisible == true)
        failure.hide()

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReasoningProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.baseURL = "https://fixture.invalid/v1"
        let app = AppState(preferences: prefs, keychain: TestKeychain(), clipboard: SystemClipboardWriter(pasteboard: pasteboard), apiClient: OpenAICompatibleClient(session: session))
        app.panelController.show(rootView: AnyView(Color.clear), on: try XCTUnwrap(NSScreen.main))
        defer { app.dismissPanel(); app.copyFeedback.hide() }
        XCTAssertFalse(app.handleCopyShortcut())
        prefs.copyShortcutAction = .copyAndClose
        XCTAssertTrue(app.handleCopyShortcut())
        XCTAssertTrue(app.panelController.isVisible, "A failed copy must leave the popup open")
        app.chat.prompt = "A fixture question"
        app.chat.submit()
        let completionDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        while app.chat.isStreaming && ContinuousClock.now < completionDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(app.chat.messages.last?.content, "The final answer.")
        XCTAssertTrue(app.handleCopyShortcut())
        XCTAssertEqual(pasteboard.string(forType: .string), "The final answer.")
        XCTAssertFalse(app.panelController.isVisible)
        XCTAssertTrue(app.copyFeedback.panel?.isVisible == true, "Feedback must survive closing the main popup")
    }

    @MainActor
    func testBubbleAndThinkingVisibilityRender() throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        var message = ChatMessage(role: .assistant, content: "Final answer")
        message.reasoning = "A provider-supplied summary."
        message.reasoningStartedAt = Date(timeIntervalSince1970: 0)
        message.reasoningEndedAt = Date(timeIntervalSince1970: 61)
        for showThinking in [false, true] {
            prefs.showThinking = showThinking
            let host = NSHostingView(rootView: VStack(alignment: .leading, spacing: 16) {
                UserMessageBubble(text: "This is a test follow-up")
                AssistantMessageView(message: message, isStreaming: false, preferences: prefs, onCopy: {})
            }.padding(16).frame(width: 600).background(Color(nsColor: .windowBackgroundColor)))
            let size = host.fittingSize
            XCTAssertGreaterThan(size.height, 70)
            host.setFrameSize(size)
            host.layoutSubtreeIfNeeded()
            try snapshot(host, name: showThinking ? "thinking-visible-bubble" : "thinking-hidden-bubble")
        }
    }

    @MainActor
    private func snapshot(_ view: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["KK_RENDER_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }
}

private struct FailedClipboard: ClipboardWriting {
    func write(_ text: String) -> Bool { false }
}

private final class ReasoningProtocol: URLProtocol, @unchecked Sendable {
    private var work: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if request.url!.path.contains("nonstream") {
            client?.urlProtocol(self, didLoad: Data(#"{"choices":[{"message":{"reasoning_content":"Provider reasoning summary.","content":"The final answer."}}]}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        client?.urlProtocol(self, didLoad: Data("data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"Provider reasoning summary.\"}}]}\n\n".utf8))
        if request.url!.path.contains("reasoning-only") || request.url!.path.contains("truncated-reasoning") {
            if request.url!.path.contains("reasoning-only") { client?.urlProtocol(self, didLoad: Data("data: [DONE]\n\n".utf8)) }
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.client?.urlProtocol(self, didLoad: Data("data: {\"choices\":[{\"delta\":{\"content\":\"The final answer.\"}}]}\n\ndata: [DONE]\n\n".utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
        self.work = work
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8, execute: work)
    }
    override func stopLoading() { work?.cancel() }
}
