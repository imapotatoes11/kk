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
        try await Task.sleep(for: .milliseconds(50))
        if let directory = ProcessInfo.processInfo.environment["KK_RENDER_DIR"], let view = controller.toolbarPanel?.contentView {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent("pointer-palette.png"))
        }
    }
}
