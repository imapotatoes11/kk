import AppKit
import XCTest
@testable import kk

final class OnboardingFocusTests: XCTestCase {
    @MainActor
    func testFirstRunAndReplayKeepOnboardingKeyAfterSettingsClose() async throws {
        _ = NSApplication.shared
        for replay in [false, true] {
            let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
            prefs.onboardingComplete = replay
            let app = AppState(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(permissionCheck: { false }))
            defer { app.onboardingWindow?.close(); app.settingsWindow?.close(); app.panelController.hide() }
            if replay {
                app.openSettings()
                XCTAssertTrue(app.settingsWindow?.isKeyWindow == true)
                app.replayOnboarding()
            } else { app.togglePanel() }
            let window = try XCTUnwrap(app.onboardingWindow)
            for _ in 0..<5 {
                try await Task.sleep(for: .milliseconds(80))
                XCTAssertTrue(window.isVisible)
                XCTAssertTrue(window.isKeyWindow, "Onboarding lost focus after its presentation handoff")
                XCTAssertTrue(NSApp.keyWindow === window)
                XCTAssertEqual(NSApp.activationPolicy(), .regular)
                XCTAssertFalse(app.panelController.isVisible)
            }
            app.togglePanel()
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertTrue(app.onboardingWindow === window, "Opening kk must reuse the active onboarding window")
            XCTAssertTrue(window.isKeyWindow)
            XCTAssertFalse(app.panelController.isVisible)
            // Explicitly focus another window: onboarding must not repeatedly grab focus back.
            app.openSettings()
            try await Task.sleep(for: .milliseconds(120))
            XCTAssertTrue(app.settingsWindow?.isKeyWindow == true)
            window.close(); app.settingsWindow?.close()
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertEqual(NSApp.activationPolicy(), .accessory)
        }
    }
}
