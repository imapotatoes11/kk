import AppKit
import XCTest
@testable import kk

final class PopupBehaviorTests: XCTestCase {
    @MainActor
    private func app() -> AppState {
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.onboardingComplete = true
        prefs.annotationsEnabled = false
        return AppState(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(permissionCheck: { false }))
    }

    @MainActor
    func testOutsideClickDismissesShortDraftsEvenWithSettingsVisible() {
        let state = app()
        state.openSettings()
        defer { state.settingsWindow?.close(); state.dismissPanel() }
        for prompt in ["", "a", "ab", "abc"] {
            state.togglePanel()
            state.chat.prompt = prompt
            XCTAssertTrue(state.panelController.isVisible)
            state.dismissEmptyPopupOnOutsideClick(at: NSPoint(x: -50000, y: -50000))
            XCTAssertEqual(state.panelController.isVisible, prompt.count > 2)
            if state.panelController.isVisible { state.dismissPanel() }
        }
    }

    @MainActor
    func testDeactivationFallbackDismissesOnlyShortDrafts() {
        let state = app()
        state.togglePanel()
        state.chat.prompt = "ab"
        state.dismissShortDraftAfterDeactivation()
        XCTAssertFalse(state.panelController.isVisible)
        state.togglePanel()
        state.chat.prompt = "Keep this"
        state.dismissShortDraftAfterDeactivation()
        XCTAssertTrue(state.panelController.isVisible)
        state.dismissPanel()
    }

    @MainActor
    func testSettingsDockAndUnfocusedWindowDoesNotAcquireFocusOnDismiss() async throws {
        let state = app()
        state.openSettings()
        let settings = try XCTUnwrap(state.settingsWindow)
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        settings.resignKey()
        state.togglePanel()
        state.dismissPanel()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(settings.isKeyWindow)
        XCTAssertTrue(settings.isVisible)
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        settings.close()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
    }

    @MainActor
    func testThresholdAndPalettePreferencesPersist() {
        let suite = "kk-palette-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.discardStrokeThreshold, 160)
        prefs.discardStrokeThreshold = 400
        prefs.palettePosition = .popup
        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.discardStrokeThreshold, 400)
        XCTAssertEqual(restored.palettePosition, .popup)
        let doc = AnnotationDocument()
        doc.begin(at: .zero, tool: .freehand, color: .red, lineWidth: 3)
        doc.move(to: CGPoint(x: 200, y: 0)); doc.finish()
        XCTAssertTrue(doc.requiresDiscardConfirmation(strokeThreshold: 160))
        XCTAssertFalse(doc.requiresDiscardConfirmation(strokeThreshold: 400))
    }

    func testPaletteEdgesAndPopupAboveBelowRemainOnScreen() {
        let visible = CGRect(x: -1800, y: 40, width: 1800, height: 1000)
        let size = CGSize(width: 480, height: 76)
        for position in PalettePosition.allCases {
            XCTAssertTrue(visible.contains(position.frame(in: visible, size: size, popup: CGRect(x: -1200, y: 600, width: 680, height: 120))))
        }
        let high = CGRect(x: -1200, y: 600, width: 680, height: 120)
        XCTAssertEqual(PalettePosition.popup.frame(in: visible, size: size, popup: high).maxY, high.minY - 12)
        let low = CGRect(x: -1200, y: 50, width: 680, height: 120)
        XCTAssertEqual(PalettePosition.popup.frame(in: visible, size: size, popup: low).minY, low.maxY + 12)
    }
}
