import AppKit
import SwiftUI
import XCTest
@testable import kk

final class AnnotationTests: XCTestCase {
    @MainActor
    func testPaletteStaysVisibleAfterManualResizeAndExpandShortcut() async throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.palettePosition = .popup
        let popup = PanelController(preferences: prefs)
        let screen = try XCTUnwrap(NSScreen.main)
        popup.show(rootView: AnyView(Color.clear), on: screen)
        let controller = AnnotationController(preferences: prefs)
        controller.textPanel = popup.panel
        controller.onActiveChange = { popup.annotationLayerActive = $0 }
        controller.begin(on: screen)
        controller.receiveCapture(ScreenSnapshot(image: try Self.image(width: 400, height: 300), data: Data()))
        defer { controller.end(); popup.hide() }
        let panel = try XCTUnwrap(popup.panel)
        let visible = screen.visibleFrame
        popup.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification, object: panel))
        panel.setFrame(NSRect(x: visible.midX - 300, y: visible.minY + 68, width: 600, height: visible.height - 88), display: true)
        try await Task.sleep(for: .milliseconds(100))
        let toolbar = try XCTUnwrap(controller.toolbarPanel)
        XCTAssertTrue(toolbar.isVisible)
        XCTAssertFalse(toolbar.frame.intersects(panel.frame))
        XCTAssertLessThanOrEqual(toolbar.frame.maxY, panel.frame.minY)
        popup.updateLayout(hasResponse: true, minimumHeight: 220, contentHeight: 5000, preferredWidth: 5000)
        popup.expandToFit()
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertFalse(toolbar.frame.intersects(panel.frame))
        XCTAssertLessThanOrEqual(toolbar.frame.maxY, panel.frame.minY)
        XCTAssertLessThanOrEqual(panel.frame.width, floor(screen.frame.width * 0.4))
        popup.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification, object: panel))
        panel.setFrame(visible, display: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(toolbar.isVisible)
        XCTAssertGreaterThan(toolbar.level.rawValue, panel.level.rawValue, "When no side fits, the palette must remain accessible above the chat")
    }

    @MainActor
    func testPreferencesPersistAndUnknownValuesFallBack() {
        let suite = "kk-annotations-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertTrue(preferences.annotationsEnabled)
        XCTAssertTrue(preferences.freezeScreen)
        XCTAssertEqual(preferences.annotationColor, .red)
        preferences.annotationsEnabled = false
        preferences.freezeScreen = false
        preferences.annotationColor = .green
        preferences.annotationTool = .arrow
        preferences.annotationLineWidth = 5
        let restored = Preferences(defaults: defaults)
        XCTAssertFalse(restored.annotationsEnabled)
        XCTAssertFalse(restored.freezeScreen)
        XCTAssertEqual(restored.annotationColor, .green)
        XCTAssertEqual(restored.annotationTool, .arrow)
        XCTAssertEqual(restored.annotationLineWidth, 5)
        defaults.set("future", forKey: "annotationTool")
        defaults.set("future", forKey: "annotationColor")
        defaults.set(-4, forKey: "annotationLineWidth")
        let invalid = Preferences(defaults: defaults)
        XCTAssertEqual(invalid.annotationTool, .freehand)
        XCTAssertEqual(invalid.annotationColor, .red)
        XCTAssertEqual(invalid.annotationLineWidth, 3)
    }

    @MainActor
    func testMultipleMarksLockStyleAndUndoClearAndPointerMode() {
        let doc = AnnotationDocument()
        for tool in AnnotationTool.allCases {
            doc.begin(at: CGPoint(x: 10, y: 10), tool: tool, color: .red, lineWidth: 3)
            doc.move(to: CGPoint(x: 40, y: 30))
            doc.move(to: CGPoint(x: 60, y: 50))
            doc.finish()
        }
        XCTAssertEqual(doc.annotations.count, 4)
        XCTAssertEqual(doc.annotations[0].points.count, 3)
        XCTAssertEqual(doc.annotations[1].points.count, 2)
        XCTAssertEqual(doc.annotations[2].tool, .rectangle)
        XCTAssertEqual(doc.annotations[3].color, .red)
        doc.undo()
        XCTAssertEqual(doc.annotations.count, 3)
        doc.isDrawing = false
        doc.begin(at: .zero, tool: .freehand, color: .blue, lineWidth: 5)
        XCTAssertNil(doc.current)
        doc.clear()
        XCTAssertTrue(doc.annotations.isEmpty)
        doc.isDrawing = true
        doc.begin(at: .zero, tool: .rectangle, color: .red, lineWidth: 3)
        doc.finish()
        XCTAssertTrue(doc.annotations.isEmpty, "Ignore accidental shape clicks")
        doc.begin(at: .zero, tool: .freehand, color: .red, lineWidth: 3)
        doc.finish()
        XCTAssertEqual(doc.annotations.count, 1, "A freehand click makes a dot")
    }

    func testEveryToolRendersAndCompositeScalesWithoutMovingBasePixels() throws {
        let image = try Self.image(width: 200, height: 100)
        let base = NSBitmapImageRep(cgImage: image)
        for tool in AnnotationTool.drawingTools {
            let mark = ScreenAnnotation(tool: tool, color: .red, lineWidth: 3,
                                        points: [CGPoint(x: 10, y: 10), CGPoint(x: 75, y: 40)])
            let result = try AnnotationRenderer.composite([mark], onto: image, canvasSize: CGSize(width: 100, height: 50))
            let bitmap = NSBitmapImageRep(cgImage: result)
            var redPixels = 0
            for x in 0..<200 {
                for y in 0..<100 {
                    let c = try XCTUnwrap(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    if c.redComponent > 0.8 && c.greenComponent < 0.4 { redPixels += 1 }
                }
            }
            XCTAssertGreaterThan(redPixels, 100, tool.title)
            XCTAssertEqual(bitmap.colorAt(x: 190, y: 90), base.colorAt(x: 190, y: 90), "Untouched pixels must survive")
            // Point (10,10) maps to native pixel (20,20), not (10,10).
            if tool != .ellipse {
                XCTAssertGreaterThan(bitmap.colorAt(x: 20, y: 80)?.redComponent ?? 0, 0.8)
            }
        }
    }

    @MainActor
    func testFrozenSessionUsesOriginalImageKeepsPopupAboveCanvasAndCleansUp() async throws {
        _ = NSApplication.shared
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.alwaysOnTop = false
        let image = try Self.image(width: 800, height: 500)
        let spy = SnapshotSpy(image: image)
        let controller = AnnotationController(preferences: preferences, capture: { id in try await spy.capture(id) })
        let popup = PanelController(preferences: preferences)
        controller.onActiveChange = { popup.annotationLayerActive = $0 }
        controller.onFocusPopup = { popup.panel?.orderFrontRegardless(); popup.panel?.makeKey() }
        let screen = try XCTUnwrap(NSScreen.main)
        controller.begin(on: screen)
        popup.show(rootView: AnyView(Color.clear), on: screen)
        defer { controller.end(); popup.hide() }
        controller.receiveCapture(ScreenSnapshot(image: image, data: try ImageProcessor.jpegData(from: image)))
        let canvasPanel = try XCTUnwrap(controller.canvasPanel)
        let toolbar = try XCTUnwrap(controller.toolbarPanel)
        XCTAssertTrue(canvasPanel.isVisible)
        XCTAssertTrue(controller.document.isFrozen)
        XCTAssertGreaterThan(try XCTUnwrap(popup.panel).level.rawValue, toolbar.level.rawValue)
        XCTAssertGreaterThan(toolbar.level.rawValue, canvasPanel.level.rawValue)
        XCTAssertEqual(canvasPanel.frame, screen.frame)
        controller.document.begin(at: CGPoint(x: 100, y: 100), tool: .arrow, color: .red, lineWidth: 3)
        controller.document.move(to: CGPoint(x: 200, y: 200))
        controller.document.finish()
        // Popup dragging stays independent of the screen-coordinate annotation model.
        let frame = try XCTUnwrap(popup.panel).frame
        popup.beginDrag()
        popup.drag(to: frame.offsetBy(dx: 90, dy: -90), cursor: NSPoint(x: screen.frame.midX, y: screen.frame.midY))
        popup.endDrag()
        XCTAssertEqual(controller.document.annotations.count, 1)
        controller.document.isDrawing = false
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertTrue(canvasPanel.ignoresMouseEvents)
        controller.suspend()
        XCTAssertFalse(canvasPanel.isVisible)
        controller.resume()
        XCTAssertTrue(canvasPanel.isVisible)
        if let directory = ProcessInfo.processInfo.environment["KK_RENDER_DIR"], let view = toolbar.contentView {
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            var redPixels = 0
            for x in 0..<bitmap.pixelsWide {
                for y in 0..<bitmap.pixelsHigh {
                    if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.redComponent > 0.8 && c.greenComponent < 0.4 { redPixels += 1 }
                }
            }
            XCTAssertGreaterThan(redPixels, 100, "Toolbar must show the selected red drawing color")
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("annotation-toolbar.png"))
        }
        let output = try await controller.prepareImage(fallback: Data())
        XCTAssertNotNil(ImageProcessor.cgImage(from: output))
        let count = await spy.count
        XCTAssertEqual(count, 0, "Freeze must not recapture a changing desktop")
        XCTAssertFalse(controller.isActive)
        XCTAssertFalse(canvasPanel.isVisible)
        XCTAssertFalse(toolbar.isVisible)
        XCTAssertTrue(controller.document.annotations.isEmpty)
        XCTAssertEqual(popup.panel?.level, .normal)
    }

    @MainActor
    func testLiveSessionRecapturesAndDisabledModeCreatesNoWindows() async throws {
        _ = NSApplication.shared
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.freezeScreen = false
        let image = try Self.image(width: 400, height: 300)
        let spy = SnapshotSpy(image: image)
        let controller = AnnotationController(preferences: preferences, capture: { id in try await spy.capture(id) })
        let screen = try XCTUnwrap(NSScreen.main)
        controller.begin(on: screen)
        controller.receiveCapture(ScreenSnapshot(image: image, data: Data()))
        XCTAssertFalse(controller.document.isFrozen)
        _ = try await controller.prepareImage(fallback: Data())
        let count = await spy.count
        XCTAssertEqual(count, 1)
        preferences.annotationsEnabled = false
        controller.begin(on: screen)
        controller.receiveCapture(ScreenSnapshot(image: image, data: Data()))
        XCTAssertFalse(controller.isActive)
        XCTAssertNil(controller.canvasPanel)
        let fallback = Data([1, 2, 3])
        let data = try await controller.prepareImage(fallback: fallback)
        XCTAssertEqual(data, fallback)
    }

    @MainActor
    func testFailedLiveCaptureRetainsMarksAndSessionForRetry() async throws {
        _ = NSApplication.shared
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.freezeScreen = false
        let controller = AnnotationController(preferences: preferences, capture: { _ in throw KKError.screenCaptureFailed("Fixture failure") })
        controller.begin(on: try XCTUnwrap(NSScreen.main))
        defer { controller.end() }
        let image = try Self.image(width: 400, height: 300)
        controller.receiveCapture(ScreenSnapshot(image: image, data: Data()))
        controller.document.begin(at: .zero, tool: .freehand, color: .red, lineWidth: 3)
        controller.document.finish()
        do { _ = try await controller.prepareImage(fallback: Data()); XCTFail("Capture should fail") }
        catch { XCTAssertTrue(controller.isActive) }
        XCTAssertFalse(controller.document.isPreparing)
        XCTAssertEqual(controller.document.annotations.count, 1)
        XCTAssertFalse(controller.canvasPanel?.ignoresMouseEvents ?? true)
    }

    @MainActor
    func testChatPreparationBlocksDuplicateSendsAndDismissDropsLateResult() async throws {
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.baseURL = "https://fixture.invalid/v1"
        let chat = ChatController(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(), apiClient: OpenAICompatibleClient(), initialScreenContext: .ready(Data([1])))
        var preparationCount = 0
        chat.prepareScreen = { _ in
            preparationCount += 1
            try? await Task.sleep(for: .milliseconds(150))
            return Data([2])
        }
        chat.prompt = "Fixture prompt"
        chat.submit()
        chat.submit()
        XCTAssertTrue(chat.isPreparingScreen)
        XCTAssertFalse(chat.canSend)
        try await Task.sleep(for: .milliseconds(40))
        chat.dismiss()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(preparationCount, 1)
        XCTAssertFalse(chat.isPreparingScreen)
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertNil(chat.currentPreviewData)
    }

    private static func image(width: Int, height: Int) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0.08, green: 0.10, blue: 0.14, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try XCTUnwrap(context.makeImage())
    }
}

private actor SnapshotSpy {
    let image: CGImage
    private(set) var count = 0
    init(image: CGImage) { self.image = image }
    func capture(_ id: CGDirectDisplayID?) throws -> ScreenSnapshot {
        count += 1
        return ScreenSnapshot(image: image, data: try ImageProcessor.jpegData(from: image))
    }
}

extension AnnotationTests {
    @MainActor
    func testPreparedImageIsSentAndRetainedOnFirstTurnOnly() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnnotationRequestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        AnnotationRequestProtocol.recorder.clear()
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.baseURL = "https://fixture.invalid/v1"
        let original = Data([1, 2, 3])
        let prepared = Data([4, 5, 6])
        let chat = ChatController(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(),
                                  apiClient: OpenAICompatibleClient(session: session), initialScreenContext: .ready(original))
        var preparedCount = 0
        var submitted = 0
        chat.prepareScreen = { data in
            XCTAssertEqual(data, original)
            preparedCount += 1
            return prepared
        }
        chat.onSubmit = { submitted += 1 }
        chat.prompt = "First fixture"
        chat.submit()
        for _ in 0..<100 {
            if chat.hasSubmitted && !chat.isStreaming { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(chat.messages.last?.content, "Fixture answer")
        XCTAssertEqual(chat.currentPreviewData, prepared)
        chat.prompt = "Followup fixture"
        chat.submit()
        for _ in 0..<100 {
            if !chat.isStreaming { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(preparedCount, 1)
        XCTAssertEqual(submitted, 2)
        let bodies = AnnotationRequestProtocol.recorder.bodies
        XCTAssertEqual(bodies.count, 2)
        for data in bodies {
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let messages = try XCTUnwrap(payload["messages"] as? [[String: Any]])
            let imageParts = messages.compactMap { $0["content"] as? [[String: Any]] }.flatMap { $0 }.filter { $0["type"] as? String == "image_url" }
            XCTAssertEqual(imageParts.count, 1)
            let imageURL = try XCTUnwrap(imageParts.first?["image_url"] as? [String: Any])
            XCTAssertEqual(imageURL["url"] as? String, "data:image/jpeg;base64," + prepared.base64EncodedString())
        }
        XCTAssertEqual(AnnotationRequestProtocol.recorder.bodies.count, 2)
    }

    @MainActor
    func testPreparationFailurePreservesPromptAndRetrySends() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AnnotationRequestProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.baseURL = "https://fixture.invalid/v1"
        let chat = ChatController(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(), apiClient: OpenAICompatibleClient(session: session), initialScreenContext: .ready(Data([1])))
        var attempts = 0
        chat.prepareScreen = { data in
            attempts += 1
            if attempts == 1 { throw KKError.screenCaptureFailed("Fixture failure") }
            return data
        }
        chat.prompt = "Keep this prompt"
        chat.submit()
        try await Task.sleep(for: .milliseconds(60))
        XCTAssertEqual(chat.prompt, "Keep this prompt")
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertTrue(chat.canSend)
        if case .error = chat.generationState {} else { XCTFail("Must surface capture failure") }
        chat.retry()
        for _ in 0..<100 {
            if chat.hasSubmitted && !chat.isStreaming { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(chat.messages.first?.content, "Keep this prompt")
        XCTAssertEqual(chat.messages.last?.content, "Fixture answer")
    }
}

private final class AnnotationRequestProtocol: URLProtocol, @unchecked Sendable {
    static let recorder = RequestRecorder()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if let data = request.httpBody { Self.recorder.append(data) }
        else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var bytes = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&bytes, maxLength: bytes.count)
                guard n > 0 else { break }
                data.append(contentsOf: bytes.prefix(n))
            }
            Self.recorder.append(data)
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("data: {\"choices\":[{\"delta\":{\"content\":\"Fixture answer\"}}]}\n\ndata: [DONE]\n\n".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Data] = []
    var bodies: [Data] { lock.withLock { storage } }
    func append(_ data: Data) { lock.withLock { storage.append(data) } }
    func clear() { lock.withLock { storage = [] } }
}


extension AnnotationTests {
    @MainActor
    func testDiscardThresholdAndSmoothingPreserveEndpoints() {
        let doc = AnnotationDocument()
        doc.begin(at: .zero, tool: .freehand, color: .red, lineWidth: 3)
        doc.move(to: CGPoint(x: 40, y: 20))
        doc.setSmoothing(true)
        doc.move(to: CGPoint(x: 80, y: 0))
        doc.finish()
        XCTAssertFalse(doc.needsDiscardConfirmation)
        XCTAssertTrue(doc.annotations[0].smoothed)
        XCTAssertEqual(doc.annotations[0].path.currentPoint, CGPoint(x: 80, y: 0))
        doc.begin(at: .zero, tool: .freehand, color: .red, lineWidth: 3)
        doc.finish()
        XCTAssertTrue(doc.needsDiscardConfirmation)
        doc.clear()
        doc.begin(at: .zero, tool: .arrow, color: .red, lineWidth: 3)
        doc.move(to: CGPoint(x: 200, y: 0))
        doc.finish()
        XCTAssertTrue(doc.needsDiscardConfirmation)
    }

    @MainActor
    func testLiveCanvasInterceptsClicksAndCanTakeKeyboardFocus() throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.freezeScreen = false
        let controller = AnnotationController(preferences: prefs)
        controller.begin(on: try XCTUnwrap(NSScreen.main))
        defer { controller.end() }
        let image = try Self.image(width: 400, height: 300)
        controller.receiveCapture(ScreenSnapshot(image: image, data: Data()))
        let panel = try XCTUnwrap(controller.canvasPanel)
        XCTAssertGreaterThan(panel.backgroundColor?.alphaComponent ?? 0, 0)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.contentView?.acceptsFirstResponder == true)
        XCTAssertTrue(controller.toolbarPanel?.isVisible == true)
    }
}

extension AnnotationTests {
    @MainActor
    func testCustomAnnotationBindingsPersistAndMatchModifiers() throws {
        let suite = "kk-local-keys-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults)
        prefs.annotationBindings["focus"] = AnnotationShortcut(keyCode: 36, modifiers: NSEvent.ModifierFlags.control.rawValue, label: "⌃Return")
        let restored = Preferences(defaults: defaults)
        let key = try XCTUnwrap(restored.annotationBindings["focus"])
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .capsLock], timestamp: 0, windowNumber: 0, context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: 36))
        XCTAssertTrue(key.matches(event))
        XCTAssertFalse(AnnotationShortcut.defaults["focus"]!.matches(event))
        prefs.annotationBindings.removeValue(forKey: "freehand")
        XCTAssertNil(Preferences(defaults: defaults).annotationBindings["freehand"])
    }

    @MainActor
    func testTinyQuickCanvasGestureDismissesButDeliberateMarkSurvives() throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let document = AnnotationDocument()
        let canvas = AnnotationCanvasView(document: document, preferences: prefs)
        var dismisses = 0
        canvas.onEmptyClick = { dismisses += 1; return true }
        func event(_ type: NSEvent.EventType, _ x: CGFloat, _ time: Double) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 20), modifierFlags: [], timestamp: time, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        canvas.mouseDown(with: try event(.leftMouseDown, 20, 0))
        canvas.mouseDragged(with: try event(.leftMouseDragged, 23, 0.1))
        canvas.mouseUp(with: try event(.leftMouseUp, 24, 0.2))
        XCTAssertEqual(dismisses, 1)
        XCTAssertTrue(document.annotations.isEmpty)
        canvas.mouseDown(with: try event(.leftMouseDown, 20, 1))
        canvas.mouseDragged(with: try event(.leftMouseDragged, 60, 1.1))
        canvas.mouseUp(with: try event(.leftMouseUp, 80, 1.2))
        XCTAssertEqual(dismisses, 1)
        XCTAssertEqual(document.annotations.count, 1)
    }
}
