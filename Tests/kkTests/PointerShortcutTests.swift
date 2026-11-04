import AppKit
import SwiftUI
import XCTest
@testable import kk

final class PointerShortcutTests: XCTestCase {
    @MainActor
    func testExistingBindingsGainPointerWithoutOverwritingConflictsOrClearedChoice() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        var legacy = AnnotationShortcut.defaults; legacy.removeValue(forKey: "pointer")
        defaults.set(try JSONEncoder().encode(legacy), forKey: "annotationBindings")
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.annotationBindings["pointer"]?.label, "V")
        prefs.annotationBindings.removeValue(forKey: "pointer")
        XCTAssertNil(Preferences(defaults: defaults).annotationBindings["pointer"], "Explicitly clearing the key must persist")
        let conflictDefaults = UserDefaults(suiteName: UUID().uuidString)!
        legacy["freehand"] = AnnotationShortcut.defaults["pointer"]
        conflictDefaults.set(try JSONEncoder().encode(legacy), forKey: "annotationBindings")
        let conflicted = Preferences(defaults: conflictDefaults)
        XCTAssertNil(conflicted.annotationBindings["pointer"])
        XCTAssertEqual(conflicted.annotationBindings["freehand"]?.label, "V")
    }

    @MainActor
    func testPointerKeyPassesThroughDesktopAndNeverInterceptsTextInput() async throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let controller = AnnotationController(preferences: prefs)
        let text = KKPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 56), styleMask: [.borderless], backing: .buffered, defer: false)
        text.isReleasedWhenClosed = false
        controller.textPanel = text
        controller.begin(on: try XCTUnwrap(NSScreen.main))
        defer { controller.end(); text.close() }
        let image = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        controller.receiveCapture(ScreenSnapshot(image: image, data: Data()))
        func key(_ code: UInt16, _ characters: String, _ window: NSWindow) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
        }
        let canvas = try XCTUnwrap(controller.canvasPanel)
        controller.focusDrawing()
        XCTAssertFalse(controller.handleToolShortcut(try key(9, "v", text)))
        XCTAssertTrue(controller.document.isDrawing)
        XCTAssertTrue(controller.handleToolShortcut(try key(9, "v", canvas)))
        XCTAssertFalse(controller.document.isDrawing)
        XCTAssertTrue(canvas.ignoresMouseEvents)
        XCTAssertTrue(controller.handleToolShortcut(try key(3, "f", canvas)))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(controller.document.isDrawing)
        XCTAssertFalse(canvas.ignoresMouseEvents)
        prefs.annotationBindings["pointer"] = .init(keyCode: 35, modifiers: 0, label: "P")
        XCTAssertFalse(controller.handleToolShortcut(try key(9, "v", canvas)))
        XCTAssertTrue(controller.handleToolShortcut(try key(35, "p", canvas)))
        XCTAssertFalse(controller.handleToolShortcut(try key(7, "x", text)))
        XCTAssertTrue(controller.handleToolShortcut(try key(7, "x", canvas)))
        XCTAssertEqual(prefs.annotationTool, .eraser)
        try await Task.sleep(for: .milliseconds(50))
        if let directory = ProcessInfo.processInfo.environment["KK_RENDER_DIR"], let view = controller.toolbarPanel?.contentView {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("pointer-palette.png"))
        }
    }

    @MainActor
    func testDeleteEventRemovesHoveredMarkOnlyWhenCanvasHasFocus() throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let controller = AnnotationController(preferences: prefs)
        let text = KKPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 56), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        text.isReleasedWhenClosed = false
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 56))
        text.contentView = editor
        text.promptEditor = editor
        controller.textPanel = text
        controller.begin(on: try XCTUnwrap(NSScreen.main))
        defer { controller.end(); text.close() }
        let image = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        controller.receiveCapture(ScreenSnapshot(image: image, data: Data()))
        let canvasPanel = try XCTUnwrap(controller.canvasPanel)
        let canvas = try XCTUnwrap(canvasPanel.contentView as? AnnotationCanvasView)
        controller.document.begin(at: CGPoint(x: 100, y: 100), tool: .freehand, color: .red, lineWidth: 3)
        controller.document.move(to: CGPoint(x: 200, y: 100)); controller.document.finish()
        let hover = try XCTUnwrap(NSEvent.mouseEvent(with: .mouseMoved, location: CGPoint(x: 150, y: 100), modifierFlags: [], timestamp: 1, windowNumber: canvasPanel.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0))
        canvas.mouseMoved(with: hover)
        func delete(in window: NSWindow) throws -> NSEvent {
            try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 2, windowNumber: window.windowNumber, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51))
        }
        editor.string = "draft"
        editor.setSelectedRange(NSRange(location: 5, length: 0))
        text.focusPrompt()
        NSApp.sendEvent(try delete(in: text))
        XCTAssertEqual(editor.string, "draf")
        XCTAssertEqual(controller.document.annotations.count, 1)
        controller.focusDrawing()
        canvas.mouseMoved(with: hover)
        NSApp.sendEvent(try delete(in: canvasPanel))
        XCTAssertTrue(controller.document.annotations.isEmpty)
    }

    @MainActor
    func testPaletteFitsNarrowestOpeningWithEraserVisible() async throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.annotationTool = .eraser
        let doc = AnnotationDocument()
        for width in [BarWidths.compact[0], 480, 680] {
            let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: width, height: 56), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let host = NSHostingView(rootView: AnnotationToolbar(document: doc, preferences: prefs, onFocus: {}, onClear: {}))
            host.sizingOptions = []
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
            func buttons(in view: NSView) -> [NSButton] {
                (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons(in: $0) }
            }
            let controls = buttons(in: host)
            XCTAssertEqual(controls.count, 10)
            let frames = controls.map { $0.convert($0.bounds, to: host) }.sorted { $0.minX < $1.minX }
            for frame in frames {
                XCTAssertGreaterThanOrEqual(frame.minX, 0)
                XCTAssertLessThanOrEqual(frame.maxX, width)
                XCTAssertGreaterThanOrEqual(frame.width, 36)
            }
            for pair in zip(frames, frames.dropFirst()) {
                XCTAssertLessThanOrEqual(pair.0.maxX, pair.1.minX + 0.5)
            }
            if let directory = ProcessInfo.processInfo.environment["KK_RENDER_DIR"] {
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("eraser-palette-\(Int(width)).png"))
            }
        }
    }
}
