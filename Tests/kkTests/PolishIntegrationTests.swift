import AppKit
import SwiftUI
import XCTest
@testable import kk

final class PolishIntegrationTests: XCTestCase {
    @MainActor
    func testSixSensitivityLevelsIncreaseCountAndLengthAndPersist() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(400.0, forKey: "discardStrokeThreshold")
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.discardSensitivityLevel, 3)
        for index in 0..<6 {
            let level = DiscardSensitivity.level(index)
            if index > 0 {
                XCTAssertGreaterThan(level.strokeCount, DiscardSensitivity.level(index - 1).strokeCount)
                XCTAssertGreaterThan(level.strokeLength, DiscardSensitivity.level(index - 1).strokeLength)
            }
            let doc = AnnotationDocument()
            for _ in 0..<level.strokeCount { doc.begin(at: .zero, tool: .freehand, color: .red, lineWidth: 3); doc.finish() }
            XCTAssertTrue(doc.requiresDiscardConfirmation(strokeThreshold: level.strokeLength, strokeCount: level.strokeCount))
            if level.strokeCount > 1 {
                let longStroke = AnnotationDocument()
                longStroke.begin(at: .zero, tool: .freehand, color: .red, lineWidth: 3)
                longStroke.move(to: CGPoint(x: level.strokeLength + 1, y: 0)); longStroke.finish()
                XCTAssertTrue(longStroke.requiresDiscardConfirmation(strokeThreshold: level.strokeLength, strokeCount: level.strokeCount))
                XCTAssertFalse(longStroke.requiresDiscardConfirmation(strokeThreshold: level.strokeLength + 2, strokeCount: level.strokeCount))
            }
            prefs.discardSensitivityLevel = index
            XCTAssertEqual(Preferences(defaults: defaults).discardSensitivityLevel, index)
        }
        prefs.showPreviewButton = false; prefs.showSubmitButton = false
        let restored = Preferences(defaults: defaults)
        XCTAssertFalse(restored.showPreviewButton); XCTAssertFalse(restored.showSubmitButton)
    }

    @MainActor
    func testPaletteOuterCellClickSwitchesTool() async throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let doc = AnnotationDocument()
        let host = NSHostingView(rootView: AnnotationToolbar(document: doc, preferences: prefs, onFocus: {}, onClear: {}))
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 480, height: 56), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let button = try XCTUnwrap(descendants(host).compactMap { $0 as? NSButton }.first { $0.accessibilityLabel() == "Ellipse" })
        XCTAssertGreaterThanOrEqual(button.bounds.width, 44)
        XCTAssertGreaterThanOrEqual(button.bounds.height, 48)
        let edge = NSPoint(x: button.frame.minX + 1, y: button.frame.maxY - 1)
        XCTAssertTrue(button.superview?.hitTest(edge) === button)
        button.performClick(nil)
        XCTAssertEqual(prefs.annotationTool, .ellipse)
    }

    @MainActor
    func testCombinedSurfacesButtonsDragRegionsAndUserMarkdown() async throws {
        _ = NSApplication.shared
        let screen = try XCTUnwrap(NSScreen.main)
        for material in PopupMaterial.allCases {
            for dark in [false, true] {
                for preview in [false, true] {
                    for submit in [false, true] {
                        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
                        prefs.popupSize = .compact; prefs.popupMaterial = material
                        prefs.appearance = dark ? .dark : .light
                        prefs.showPreviewButton = preview; prefs.showSubmitButton = submit
                        let chat = ChatController(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(permissionCheck: { false }), apiClient: OpenAICompatibleClient(), initialScreenContext: .ready(Data([1])))
                        chat.prompt = "**plain input**"
                        let controller = PanelController(preferences: prefs)
                        controller.show(rootView: AnyView(PanelRootView(chat: chat, preferences: prefs, panelController: controller, onOpenSettings: {}, onDismiss: {})), on: screen)
                        let annotations = AnnotationController(preferences: prefs)
                        annotations.textPanel = controller.panel
                        annotations.begin(on: screen)
                        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 100, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
                        bitmap.bitmapData?.initialize(repeating: 0, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
                        annotations.receiveCapture(ScreenSnapshot(image: try XCTUnwrap(bitmap.cgImage), data: Data()))
                        try await Task.sleep(for: .milliseconds(100))
                        let popup = try XCTUnwrap(controller.panel)
                        let palette = try XCTUnwrap(annotations.toolbarPanel)
                        XCTAssertEqual(popup.frame.width, palette.frame.width)
                        XCTAssertEqual(popup.frame.height, palette.frame.height)
                        let host = try XCTUnwrap(popup.contentView)
                        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
                        let editor = try XCTUnwrap(views(host).compactMap { $0 as? NSTextView }.first)
                        XCTAssertEqual(editor.string, "**plain input**", "The editor stays plain Markdown source")
                        let buttonHit = host.hitTest(NSPoint(x: host.bounds.maxX - 36, y: host.bounds.midY))
                        XCTAssertFalse(buttonHit.map { String(describing: type(of: $0)).contains("DragView") } ?? true, "Settings remains clickable")
                        let topPoint = NSPoint(x: host.bounds.midX, y: host.bounds.maxY - 2)
                        let hit = host.hitTest(topPoint)
                        XCTAssertTrue(hit.map { String(describing: type(of: $0)).contains("DragView") } ?? false, "Top padding must hit the native drag target")
                        let key = "\(material.rawValue)-\(dark ? "dark" : "light")-\(preview)-\(submit)"
                        try save(host, name: "popup-" + key)
                        try save(try XCTUnwrap(palette.contentView), name: "palette-" + key)
                        annotations.end(); controller.hide()
                    }
                }
            }
        }
        let bubble = NSHostingView(rootView: UserMessageBubble(text: "# A heading\n\n**Bold** and `code`\n\n- One\n- Two").padding(16).frame(width: 600).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: 50, y: 50, width: 600, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = bubble; window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        try save(bubble, name: "user-markdown")
    }

    @MainActor
    private func save(_ view: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["KK_RENDER_DIR"] else { return }
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }
}
