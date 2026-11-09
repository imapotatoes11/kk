import AppKit
import XCTest
import SwiftUI
@testable import kk

final class ConversationRevisionTests: XCTestCase {
    @MainActor
    func testEarlierEditRevisesDependentTurnsAtomicallyAndKeepsIndependentTurn() async throws {
        let fixture = RevisionFixture([
            .text("Use two apples."), .text("Four apples."), .text("Paris."),
            .text("Use three pears.", delay: 0.1),
            .text(#"{"prompt":"Double those pears","regenerateAnswer":false}"#),
            .text("Six pears."),
            .text(#"{"prompt":"Capital of France?","regenerateAnswer":false}"#)
        ])
        let (chat, session) = makeChat(fixture, image: Data([1, 2, 3]))
        defer { chat.reset(); session.invalidateAndCancel() }
        for prompt in ["Two apples", "Double those apples", "Capital of France?"] { try await send(prompt, chat) }
        let original = chat.messages
        chat.prompt = "Unsent follow-up"
        chat.beginEditing(responseID: original[1].id)
        XCTAssertEqual(chat.editingMessageID, original[0].id)
        XCTAssertFalse(chat.canSend)
        chat.editedPrompt = "Three pears"
        chat.sendEdit()
        XCTAssertTrue(chat.isRevising)
        XCTAssertEqual(chat.messages, original, "The active conversation stays intact until the entire cascade succeeds")
        try await wait { !chat.isStreaming }
        XCTAssertNil(chat.revisionNotice)
        XCTAssertEqual(chat.messages.map(\.content), ["Three pears", "Use three pears.", "Double those pears", "Six pears.", "Capital of France?", "Paris."])
        XCTAssertEqual(chat.messages.map(\.id), original.map(\.id))
        XCTAssertEqual(chat.messages[0].screenData, original[0].screenData)
        XCTAssertTrue(chat.messages[2].isInferred)
        XCTAssertFalse(chat.messages[0].isInferred)
        XCTAssertEqual(chat.messages[2].previousVersions.first?.content, "Double those apples")
        XCTAssertEqual(chat.messages[1].previousVersions.first?.content, "Use two apples.")
        XCTAssertTrue(chat.messages[4].previousVersions.isEmpty)
        XCTAssertTrue(chat.messages[5].previousVersions.isEmpty)
        XCTAssertEqual(chat.prompt, "Unsent follow-up")
        XCTAssertFalse(chat.clipboardTranscript.contains("apples"))
        XCTAssertTrue(chat.clipboardTranscript.contains("Six pears."))
        let requests = fixture.requests
        XCTAssertEqual(requests.count, 7, "The independent answer is kept without another generation")
        let regenerated = try XCTUnwrap(requests[3]["messages"] as? [[String: Any]])
        XCTAssertEqual(regenerated.count, 2, "The first replacement must not see its old answer or later turns")
        XCTAssertTrue(String(describing: regenerated.last!).contains("AQID"), "Retry/edit keeps the original screenshot")
    }

    @MainActor
    func testFailureRollsBackAndRetryRepeatsTheFailedRevision() async throws {
        let fixture = RevisionFixture([.text("First"), .text("Second"), .text("New first"), .text("not JSON"),
            .text("New first, again"), .text(#"{"prompt":"Next","regenerateAnswer":false}"#)])
        let (chat, session) = makeChat(fixture)
        defer { chat.reset(); session.invalidateAndCancel() }
        try await send("Start", chat); try await send("Next", chat)
        let original = chat.messages
        chat.retry(responseID: original[1].id)
        try await wait { !chat.isStreaming }
        XCTAssertEqual(chat.messages, original)
        XCTAssertNil(chat.revisionPreview)
        XCTAssertTrue(chat.revisionNotice?.contains("original conversation was kept") == true)
        chat.retry()
        try await wait { !chat.isStreaming }
        XCTAssertEqual(chat.messages[1].content, "New first, again")
        XCTAssertEqual(chat.messages[1].previousVersions.count, 1)
        XCTAssertEqual(chat.messages[3].content, "Second")
    }

    @MainActor
    func testStoppingOrResettingCascadeDiscardsEveryPartialRevision() async throws {
        for reset in [false, true] {
            let fixture = RevisionFixture([.text("First"), .text("Second"), .text("New first"),
                .text(#"{"prompt":"New next","regenerateAnswer":true}"#, delay: 0.2)])
            let (chat, session) = makeChat(fixture)
            defer { chat.reset(); session.invalidateAndCancel() }
            try await send("Start", chat); try await send("Next", chat)
            let original = chat.messages
            chat.retry(responseID: original[1].id)
            try await wait { chat.revisionProgress?.hasPrefix("Checking later") == true }
            if reset { chat.reset() } else { chat.stop() }
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(chat.messages, reset ? [] : original)
            XCTAssertFalse(chat.isRevising)
            XCTAssertFalse(chat.isStreaming)
            XCTAssertNil(chat.revisionPreview)
        }
    }

    @MainActor
    func testEditingCancellationPreservesDraftAndLatestRetryHasVersionHistory() async throws {
        let fixture = RevisionFixture([.text("Original"), .text("Retried")])
        let (chat, session) = makeChat(fixture)
        defer { chat.reset(); session.invalidateAndCancel() }
        try await send("Question", chat)
        let original = chat.messages
        chat.prompt = "Draft"
        chat.beginEditing(responseID: original[1].id)
        chat.editedPrompt = "Changed then cancelled"
        chat.cancelEditing()
        XCTAssertEqual(chat.messages, original)
        XCTAssertEqual(chat.prompt, "Draft")
        XCTAssertTrue(chat.canSend)
        chat.retry(responseID: original[1].id)
        try await wait { !chat.isStreaming }
        XCTAssertEqual(chat.messages[1].content, "Retried")
        XCTAssertEqual(chat.messages[1].displayingVersion(0).content, "Original")
        XCTAssertEqual(chat.messages[1].content, "Retried", "Inspecting history cannot change the authoritative version")
        XCTAssertEqual(fixture.requests.count, 2, "Latest retry needs no downstream assessment")
    }

    func testAssessmentRejectsInvalidOrEmptyRewriteAndForcesRegenerationForChangedInput() throws {
        XCTAssertThrowsError(try ConversationRevision.parseAssessment("bad", originalPrompt: "Question", allowsEmpty: false))
        XCTAssertThrowsError(try ConversationRevision.parseAssessment(#"{"prompt":"","regenerateAnswer":true}"#, originalPrompt: "Question", allowsEmpty: false))
        let changed = try ConversationRevision.parseAssessment(#"{"prompt":"New","regenerateAnswer":false}"#, originalPrompt: "Old", allowsEmpty: false)
        XCTAssertTrue(changed.regenerateAnswer)
        XCTAssertEqual(try ConversationRevision.parseAssessment(#"{"prompt":"","regenerateAnswer":false}"#, originalPrompt: "", allowsEmpty: true).prompt, "")
    }

    @MainActor
    func testInlineEditDisablesFollowupAndKeyboardCancelSendAndNewlineWork() async throws {
        _ = NSApplication.shared
        let fixture = RevisionFixture([.text("Original answer"), .text("Edited answer")])
        let (chat, session) = makeChat(fixture)
        let controller = PanelController(preferences: chat.preferences)
        controller.show(rootView: AnyView(PanelRootView(chat: chat, preferences: chat.preferences, panelController: controller, onOpenSettings: {}, onDismiss: { controller.hide() })), on: try XCTUnwrap(NSScreen.main))
        defer { chat.reset(); controller.hide(); session.invalidateAndCancel() }
        try await send("Original question", chat)
        try await Task.sleep(for: .milliseconds(350))
        let panel = try XCTUnwrap(controller.panel)
        let composer = try XCTUnwrap(panel.promptEditor)
        let response = chat.messages[1].id
        chat.prompt = "Unsent draft"
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        func editField() throws -> PromptTextView {
            try XCTUnwrap(views(try XCTUnwrap(panel.contentView)).compactMap { $0 as? PromptScrollView }.first { !$0.registersAsComposer }?.documentView as? PromptTextView)
        }
        func key(_ editor: NSTextView, code: UInt16, characters: String, modifiers: NSEvent.ModifierFlags = []) throws {
            editor.keyDown(with: try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: panel.windowNumber,
                context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)))
        }
        chat.beginEditing(responseID: response)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(composer.isEditable)
        XCTAssertTrue(panel.promptEditor === composer, "Inline editor must not replace the follow-up focus target")
        let editor = try editField()
        XCTAssertTrue(panel.firstResponder === editor)
        try render(try XCTUnwrap(panel.contentView), name: "inline-edit")
        try key(editor, code: 36, characters: "\r", modifiers: .shift)
        XCTAssertTrue(chat.editedPrompt.contains("\n"))
        XCTAssertFalse(chat.isStreaming)
        try key(editor, code: 53, characters: "\u{1b}")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(chat.editingMessageID)
        XCTAssertTrue(panel.isVisible, "Escape cancels editing instead of closing the popup")
        XCTAssertEqual(chat.prompt, "Unsent draft")
        XCTAssertTrue(composer.isEditable)
        chat.beginEditing(responseID: response)
        chat.editedPrompt = "Edited question"
        try await Task.sleep(for: .milliseconds(200))
        try key(try editField(), code: 36, characters: "\r")
        try await wait { !chat.isStreaming && chat.editingMessageID == nil }
        XCTAssertEqual(chat.messages[0].content, "Edited question")
        XCTAssertEqual(chat.messages[1].content, "Edited answer")
        XCTAssertEqual(chat.prompt, "Unsent draft")
    }

    @MainActor
    func testVersionPagerBrowsesHistoryAndCopyAlwaysUsesLatestInLightAndDark() async throws {
        _ = NSApplication.shared
        let fixture = RevisionFixture([.text("Original answer"), .text("Latest answer")])
        let (chat, session) = makeChat(fixture)
        defer { chat.reset(); session.invalidateAndCancel() }
        try await send("Question", chat)
        chat.retry(responseID: chat.messages[1].id)
        try await wait { !chat.isStreaming }
        for dark in [false, true] {
            var copied: String?
            let host = NSHostingView(rootView: ConversationMessageRow(message: chat.messages[1], chat: chat, preferences: chat.preferences,
                onCopy: { copied = chat.messages[1].content }).padding(16).frame(width: 500, height: 200, alignment: .topLeading)
                .environment(\.colorScheme, dark ? .dark : .light).background(Color(nsColor: .windowBackgroundColor)))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            window.contentView = host
            window.orderFront(nil)
            window.acceptsMouseMovedEvents = true
            window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: NSPoint(x: 100, y: 150), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 0, pressure: 0)))
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(200))
            func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
            // SwiftUI's native button wrappers have empty AppKit labels; use
            // their rendered row positions instead of private accessibility nodes.
            let buttons = views(host).compactMap { $0 as? NSButton }
            XCTAssertEqual(buttons.count, 5)
            let byRow = buttons.sorted { $0.convert($0.bounds, to: nil).minY < $1.convert($1.bounds, to: nil).minY }
            let pager = byRow.prefix(2).sorted { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX }
            let copy = try XCTUnwrap(byRow.dropFirst(2).min { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX })
            let next = try XCTUnwrap(pager.last)
            let previous = try XCTUnwrap(pager.first)
            previous.performClick(nil)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(next.isEnabled)
            try render(host, name: dark ? "revision-history-dark" : "revision-history-light")
            copy.performClick(nil)
            XCTAssertEqual(copied, "Latest answer")
            XCTAssertEqual(chat.messages[1].content, "Latest answer")
            next.performClick(nil)
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertFalse(next.isEnabled)
        }
    }

    @MainActor
    func testCancellingRevisionResumesPausedDiagramChecks() async throws {
        let code = "flowchart LR\nA-->B"
        let fixture = RevisionFixture([.text("```mermaid\n" + code + "\n```"), .text("Replacement", delay: 0.2)])
        let (chat, session) = makeChat(fixture)
        defer { chat.reset(); session.invalidateAndCancel() }
        var validations = 0
        chat.validateDiagram = { _ in
            validations += 1
            try? await Task.sleep(for: .milliseconds(150))
            return nil
        }
        try await send("Diagram", chat)
        try await wait { validations == 1 }
        XCTAssertNotNil(chat.diagramRepairs.status(for: code))
        chat.retry(responseID: chat.messages[1].id)
        chat.stop()
        try await wait { validations >= 2 }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertNil(chat.diagramRepairs.status(for: code), "Cancelled work must not leave a checking/repairing badge behind")
        XCTAssertTrue(chat.messages[1].content.contains(code))
    }

    @MainActor
    private func render(_ view: NSView, name: String) throws {
        guard let folder = ProcessInfo.processInfo.environment["KK_RENDER_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: folder).appendingPathComponent(name + ".png"))
    }

    @MainActor
    private func makeChat(_ fixture: RevisionFixture, image: Data? = nil) -> (ChatController, URLSession) {
        let host = UUID().uuidString.lowercased() + ".fixture.invalid"
        RevisionProtocol.register(fixture, host: host)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RevisionProtocol.self]
        let session = URLSession(configuration: config)
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.baseURL = "https://\(host)/v1"
        return (ChatController(preferences: preferences, keychain: TestKeychain(), captureService: ScreenCaptureService(permissionCheck: { false }), apiClient: OpenAICompatibleClient(session: session), initialScreenContext: image.map(ScreenContextState.ready) ?? .disabled), session)
    }

    @MainActor
    private func send(_ text: String, _ chat: ChatController) async throws {
        chat.prompt = text; chat.submit()
        try await wait { !chat.isStreaming }
    }
    @MainActor
    private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(4))
        while !condition(), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
}

private final class RevisionFixture: @unchecked Sendable {
    struct Reply {
        let content: String
        let delay: TimeInterval
        static func text(_ content: String, delay: TimeInterval = 0) -> Self { Self(content: content, delay: delay) }
    }
    private let lock = NSLock()
    private var replies: [Reply]
    private var recorded: [[String: Any]] = []
    var requests: [[String: Any]] { lock.withLock { recorded } }
    init(_ replies: [Reply]) { self.replies = replies }
    func next(_ request: URLRequest) -> Reply {
        lock.withLock {
            var body = request.httpBody ?? Data()
            if body.isEmpty, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            recorded.append((try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:])
            return replies.isEmpty ? .text("Unexpected request") : replies.removeFirst()
        }
    }
}

private final class RevisionProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var fixtures: [String: RevisionFixture] = [:]
    static func register(_ fixture: RevisionFixture, host: String) { lock.withLock { fixtures[host] = fixture } }
    private let cancellationLock = NSLock()
    private var cancelled = false
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host?.hasSuffix(".fixture.invalid") == true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let fixture = Self.lock.withLock({ Self.fixtures[request.url?.host ?? ""] }) else { return }
        let reply = fixture.next(request)
        DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { [self] in
            guard !cancellationLock.withLock({ cancelled }) else { return }
            let data = try! JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": reply.content]]]])
            let body = "data: " + String(decoding: data, as: UTF8.self) + "\n\ndata: [DONE]\n\n"
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() { cancellationLock.withLock { cancelled = true } }
}
