import AppKit
import SwiftUI
import XCTest
@testable import kk

final class InteractionPolishTests: XCTestCase {
    func testDisplaySelectionAcrossNegativeCoordinatesAndStraddlingWindows() {
        let frames = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: 0, width: 1920, height: 1080), CGRect(x: 0, y: 900, width: 1200, height: 800)]
        let cursor = CGPoint(x: -200, y: 400)
        let active = CGRect(x: 100, y: 200, width: 800, height: 500)
        XCTAssertEqual(DisplayResolver.selectedIndices(mode: .cursor, frames: frames, cursor: cursor, activeWindow: active), [1])
        XCTAssertEqual(DisplayResolver.selectedIndices(mode: .active, frames: frames, cursor: cursor, activeWindow: active), [0])
        XCTAssertEqual(DisplayResolver.selectedIndices(mode: .all, frames: frames, cursor: cursor, activeWindow: active), [1, 0, 2])
        XCTAssertEqual(DisplayResolver.selectedIndices(mode: .active, frames: frames, cursor: cursor, activeWindow: CGRect(x: -600, y: 200, width: 800, height: 500)), [1])
        XCTAssertEqual(DisplayResolver.selectedIndices(mode: .active, frames: frames, cursor: cursor, activeWindow: nil, fallback: 2), [2])
        XCTAssertEqual(DisplayResolver.selectedIndices(mode: .cursor, frames: frames, cursor: CGPoint(x: 9999, y: 9999), activeWindow: nil, fallback: 2), [2])
        XCTAssertEqual(DisplayResolver.selectedIndices(mode: .all, frames: [], cursor: cursor, activeWindow: nil), [])
    }

    @MainActor
    func testMultipleCaptureImagesSurviveSendRetryAndRemoval() async throws {
        _ = NSApplication.shared
        let session = fixtureSession()
        defer { session.invalidateAndCancel() }
        let prefs = preferences()
        let probe = CaptureSequence()
        let chat = ChatController(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(permissionCheck: { true }), apiClient: OpenAICompatibleClient(session: session), capture: { try await probe.capture($0) })
        defer { chat.reset() }
        let screen = try XCTUnwrap(NSScreen.main)
        // Repeated NSScreen objects stand in for three displays; selection geometry is tested separately.
        chat.beginCapture(for: screen, additionalScreens: [screen, screen])
        try await wait { chat.currentPreviewImages.count == 3 }
        let original = chat.currentPreviewImages
        let originalNames = chat.capturedScreenNames
        chat.preparePreview = { _ in original[0] }
        chat.togglePreview()
        XCTAssertEqual(chat.currentPreviewImages, original)
        let host = NSHostingView(rootView: ScreenPreviewView(chat: chat).frame(width: 400).background(Color(nsColor: .windowBackgroundColor)))
        let window = mount(host, size: NSSize(width: 400, height: 500))
        defer { window.close() }
        try await settle(host)
        try render(host, name: "all-displays-preview")
        let scroll = try XCTUnwrap(views(host).compactMap { $0 as? NSScrollView }.first)
        XCTAssertGreaterThan(scroll.documentView?.bounds.height ?? 0, scroll.contentSize.height)
        scroll.documentView?.scroll(NSPoint(x: 0, y: scroll.documentView?.bounds.height ?? 0))
        try render(host, name: "all-displays-preview-bottom")
        chat.prompt = "Compare these displays"
        chat.submit()
        try await wait { !chat.isStreaming }
        XCTAssertEqual(chat.messages.first?.screenData, original[0])
        XCTAssertEqual(chat.messages.first?.additionalScreenData, Array(original.dropFirst()))
        let request = ChatRequestBuilder.messages(for: chat.messages, firstImage: nil, appendingUserText: "next", appendingImage: Data([9]), additionalImages: [Data([10])])
        guard case .parts(let old) = request[1].content, case .parts(let next) = request.last?.content else { return XCTFail("Expected multi-image parts") }
        XCTAssertEqual(old.count, 4)
        XCTAssertEqual(next.count, 3)
        // A new draft has a different capture set, but retry must restore the original set and labels.
        chat.beginCapture(for: screen)
        try await wait { chat.currentPreviewImages.count == 1 }
        chat.retry()
        try await wait { !chat.isStreaming }
        XCTAssertEqual(chat.currentPreviewImages, original)
        XCTAssertEqual(chat.capturedScreenNames, originalNames)
        XCTAssertEqual(chat.messages.filter { $0.role == .user }.count, 1)
        chat.removeScreen()
        XCTAssertTrue(chat.currentPreviewImages.isEmpty)
        XCTAssertTrue(chat.capturedScreenNames.isEmpty)
        chat.prompt = "text only"
        chat.submit()
        try await wait { !chat.isStreaming }
        XCTAssertNil(chat.messages.filter { $0.role == .user }.last?.screenData)
        XCTAssertEqual(chat.messages.filter { $0.role == .user }.last?.additionalScreenData, [])
    }

    @MainActor
    func testCaptureBatchFailureAndCancellationNeverPublishPartialImages() async throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let failure = CaptureSequence(failAt: 2)
        let chat = ChatController(preferences: preferences(), keychain: TestKeychain(), captureService: ScreenCaptureService(permissionCheck: { true }), apiClient: OpenAICompatibleClient(), capture: { try await failure.capture($0) })
        var annotationStarts = 0
        chat.onCaptureReady = { _ in annotationStarts += 1 }
        chat.beginCapture(for: screen, additionalScreens: [screen, screen])
        try await wait { if case .failed = chat.screenContextState { true } else { false } }
        XCTAssertTrue(chat.currentPreviewImages.isEmpty)
        XCTAssertEqual(annotationStarts, 0)
        let slow = CaptureSequence(delay: .milliseconds(100))
        let canceled = ChatController(preferences: preferences(), keychain: TestKeychain(), captureService: ScreenCaptureService(permissionCheck: { true }), apiClient: OpenAICompatibleClient(), capture: { try await slow.capture($0) })
        canceled.beginCapture(for: screen, additionalScreens: [screen, screen])
        try await Task.sleep(for: .milliseconds(150))
        canceled.dismiss()
        try await Task.sleep(for: .milliseconds(220))
        XCTAssertTrue(canceled.currentPreviewImages.isEmpty)
        guard case .disabled = canceled.screenContextState else { return XCTFail("Stale capture result after dismissal") }
        chat.reset()
    }

    @MainActor
    func testOtherDisplayRefreshFailurePreservesDraftAndAnnotations() async throws {
        let prefs = preferences()
        let annotations = AnnotationController(preferences: prefs)
        annotations.begin(on: try XCTUnwrap(NSScreen.main))
        annotations.document.begin(at: .zero, tool: .freehand, color: .red, lineWidth: 3)
        annotations.document.move(to: CGPoint(x: 50, y: 50)); annotations.document.finish()
        defer { annotations.end() }
        let chat = ChatController(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(), apiClient: OpenAICompatibleClient(), initialScreenContext: .ready(Data([1])))
        defer { chat.reset() }
        var primaryPrepared = false
        chat.prepareAdditionalScreens = { throw KKError.screenCaptureFailed("Second display disconnected") }
        chat.prepareScreen = { data in primaryPrepared = true; annotations.end(); return data }
        chat.prompt = "Keep these marks"
        chat.submit()
        try await wait { !chat.isPreparingScreen }
        XCTAssertFalse(primaryPrepared)
        XCTAssertEqual(annotations.document.annotations.count, 1)
        XCTAssertEqual(chat.prompt, "Keep these marks")
        XCTAssertTrue(chat.messages.isEmpty)
        guard case .error = chat.generationState else { return XCTFail("Must explain capture failure") }
    }

    @MainActor
    func testStreamingEditorAcceptsNextDraftAndStopButtonInterrupts() async throws {
        _ = NSApplication.shared
        let prefs = preferences(); prefs.baseURL = "https://fixture.invalid/slow"; prefs.showSubmitButton = false
        let session = fixtureSession()
        defer { session.invalidateAndCancel() }
        let chat = ChatController(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(permissionCheck: { false }), apiClient: OpenAICompatibleClient(session: session))
        let controller = PanelController(preferences: prefs)
        controller.show(rootView: AnyView(PanelRootView(chat: chat, preferences: prefs, panelController: controller, onOpenSettings: {}, onDismiss: {})), on: try XCTUnwrap(NSScreen.main))
        defer { chat.reset(); controller.hide() }
        chat.prompt = "first"; chat.submit()
        let host = try XCTUnwrap(controller.panel?.contentView)
        try await settle(host)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertTrue(chat.isStreaming)
        let editor = try XCTUnwrap(views(host).compactMap { $0 as? NSTextView }.first)
        XCTAssertTrue(editor.isEditable)
        editor.insertText("next question", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertEqual(chat.prompt, "next question")
        XCTAssertFalse(chat.canSend)
        editor.doCommand(by: #selector(NSTextView.insertNewline(_:)))
        XCTAssertEqual(chat.messages.filter { $0.role == .user }.count, 1)
        XCTAssertEqual(chat.prompt, "next question")
        try render(host, name: "streaming-editable-stop")
        let stop = try XCTUnwrap(views(host).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Stop answer" })
        XCTAssertTrue(stop.isEnabled)
        stop.performClick(nil)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(chat.isStreaming)
        XCTAssertEqual(chat.prompt, "next question")
    }

    @MainActor
    func testCopyCapsulesFitTextAndRenderEveryMaterialAndAppearance() async throws {
        _ = NSApplication.shared
        let prefs = preferences()
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let feedback = CopyFeedbackController(clipboard: SystemClipboardWriter(pasteboard: pasteboard), preferences: prefs)
        defer { feedback.hide() }
        for dark in [false, true] {
            prefs.appearance = dark ? .dark : .light
            for material in PopupMaterial.allCases {
                prefs.popupMaterial = material
                XCTAssertTrue(feedback.copy("answer", near: nil))
                let panel = try XCTUnwrap(feedback.panel)
                let firstWidth = panel.frame.width
                XCTAssertLessThan(firstWidth, 230)
                XCTAssertGreaterThan(firstWidth, 100)
                XCTAssertLessThan(panel.frame.height, 60)
                XCTAssertTrue(panel.ignoresMouseEvents)
                XCTAssertEqual(panel.appearance?.name, dark ? .darkAqua : .aqua)
                let view = try XCTUnwrap(panel.contentView)
                try await settle(view)
                try render(view, name: "copy-\(material.rawValue)-\(dark ? "dark" : "light")")
                if material == .translucent && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                    XCTAssertTrue(views(view).contains { ($0 as? NSVisualEffectView)?.material == .hudWindow })
                }
                feedback.copy("answer", near: nil, successMessage: "Chat copied")
                XCTAssertLessThan(panel.frame.width, firstWidth, "Toast must follow text width")
            }
        }
        XCTAssertEqual(pasteboard.string(forType: .string), "answer")
    }

    @MainActor
    func testArrowCurvesTowardAppListAndGeneralIsFirst() async throws {
        _ = NSApplication.shared
        let settings = CGRect(x: 16, y: 180, width: 740, height: 620)
        let target = PermissionArrowGeometry.target(in: settings)
        XCTAssertGreaterThan(target.x, settings.minX + 240)
        let start = CGPoint(x: 232, y: 120)
        let path = PermissionArrowGeometry.path(from: start, to: target)
        XCTAssertLessThan(path.boundingBoxOfPath.minX, start.x - 10)
        let arrow = PermissionDragArrow()
        arrow.show(from: start, to: target)
        defer { arrow.hide() }
        let panel = try XCTUnwrap(arrow.panel)
        XCTAssertTrue(panel.frame.contains(path.boundingBoxOfPath))
        XCTAssertTrue(panel.ignoresMouseEvents)
        try render(try XCTUnwrap(panel.contentView), name: "permission-curved-arrow")
        let prefs = preferences(); prefs.captureDisplayMode = .all
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let stored = Preferences(defaults: defaults); stored.captureDisplayMode = .all
        XCTAssertEqual(Preferences(defaults: defaults).captureDisplayMode, .all)
        stored.resetCustomization(); XCTAssertEqual(stored.captureDisplayMode, .cursor)
        let app = AppState(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(permissionCheck: { false }))
        let controller = SettingsWindowController(appState: app)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        window.orderFront(nil)
        XCTAssertEqual(controller.selection.section, .general)
        XCTAssertEqual(window.toolbar?.items.filter { $0.itemIdentifier != .flexibleSpace }.prefix(2).map(\.label), ["General", "Inference"])
        try await settle(try XCTUnwrap(window.contentView))
        window.setContentSize(NSSize(width: 640, height: 1120))
        try await settle(try XCTUnwrap(window.contentView))
        try render(try XCTUnwrap(window.contentView), name: "general-all-displays")
    }

    @MainActor private func preferences() -> Preferences {
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.baseURL = "https://fixture.invalid/v1"; prefs.onboardingComplete = true
        return prefs
    }
    private func fixtureSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [InteractionProtocol.self]
        return URLSession(configuration: config)
    }
    @MainActor private func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertTrue(condition())
    }
    @MainActor private func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
    @MainActor private func mount(_ host: NSView, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host; window.orderFront(nil); return window
    }
    @MainActor private func settle(_ view: NSView) async throws {
        try await Task.sleep(for: .milliseconds(200)); view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
    }
    @MainActor private func render(_ view: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["KK_RENDER_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }
}

private actor CaptureSequence {
    var count = 0
    let failAt: Int?
    let delay: Duration
    init(failAt: Int? = nil, delay: Duration = .zero) { self.failAt = failAt; self.delay = delay }
    func capture(_ id: CGDirectDisplayID?) async throws -> ScreenSnapshot {
        count += 1
        if count == failAt { throw KKError.screenCaptureFailed("Fixture display disconnected") }
        try await Task.sleep(for: delay)
        let context = try XCTUnwrap(CGContext(data: nil, width: 240, height: 160, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: CGFloat(count % 2), green: CGFloat((count + 1) % 2), blue: 0.4, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
        let image = try XCTUnwrap(context.makeImage())
        return ScreenSnapshot(image: image, data: try ImageProcessor.jpegData(from: image))
    }
}

private final class InteractionProtocol: URLProtocol, @unchecked Sendable {
    private var work: DispatchWorkItem?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("data: {\"choices\":[{\"delta\":{\"content\":\"A partial answer.\"}}]}\n\n".utf8))
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.client?.urlProtocol(self, didLoad: Data("data: [DONE]\n\n".utf8)); self.client?.urlProtocolDidFinishLoading(self)
        }
        self.work = work
        DispatchQueue.global().asyncAfter(deadline: .now() + (request.url!.path.contains("slow") ? 5 : 0.01), execute: work)
    }
    override func stopLoading() { work?.cancel() }
}
