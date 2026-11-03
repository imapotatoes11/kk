import AppKit
import XCTest
@testable import kk

final class PromptFocusTests: XCTestCase {
    @MainActor
    func testOpeningAndReturningFromAnnotationsFocusesActualEditor() async throws {
        _ = NSApplication.shared
        let image = try XCTUnwrap(CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let snapshot = ScreenSnapshot(image: image, data: try ImageProcessor.jpegData(from: image))
        for size in PopupSize.allCases {
            for freeze in [false, true] {
                let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
                prefs.onboardingComplete = true; prefs.popupSize = size
                prefs.annotationsEnabled = true; prefs.freezeScreen = freeze
                let capture = ScreenCaptureService(permissionCheck: { true }, captureAttempt: { _ in
                    try await Task.sleep(for: .milliseconds(100))
                    return snapshot
                })
                let app = AppState(preferences: prefs, keychain: TestKeychain(), captureService: capture)
                app.togglePanel()
                defer { app.dismissPanel() }
                let popup = try XCTUnwrap(app.panelController.panel)
                let deadline = ContinuousClock.now.advanced(by: .seconds(3))
                while (app.annotations.canvasPanel == nil || popup.promptEditor == nil) && ContinuousClock.now < deadline {
                    try await Task.sleep(for: .milliseconds(20))
                }
                XCTAssertNotNil(app.annotations.canvasPanel)
                let editor = try XCTUnwrap(popup.promptEditor)
                XCTAssertTrue(popup.isKeyWindow)
                XCTAssertTrue(popup.firstResponder === editor, "Overlay creation must leave the insertion point in the prompt")
                editor.insertText("Typing immediately", replacementRange: NSRange(location: 0, length: 0))
                XCTAssertEqual(app.chat.prompt, "Typing immediately")
                app.annotations.focusDrawing()
                XCTAssertTrue(app.annotations.canvasPanel?.isKeyWindow == true)
                app.annotations.onFocusPopup?()
                XCTAssertTrue(popup.isKeyWindow)
                XCTAssertTrue(popup.firstResponder === editor, "Return-to-text must focus the editor, not just the window")
                app.dismissPanel()
            }
        }
    }
}
