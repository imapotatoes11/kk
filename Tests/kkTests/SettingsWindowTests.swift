import AppKit
import XCTest
@testable import kk

final class SettingsWindowTests: XCTestCase {
    @MainActor
    func testSettingsWindowOpensAndCanReopen() {
        _ = NSApplication.shared
        let state = AppState()
        state.openSettings()
        let window = state.settingsWindow
        XCTAssertNotNil(window)
        XCTAssertEqual(window?.title, "kk Settings")
        XCTAssertTrue(window?.isVisible == true)
        XCTAssertGreaterThanOrEqual(window?.contentView?.bounds.height ?? 0, 300)
        XCTAssertGreaterThanOrEqual(window?.contentView?.bounds.width ?? 0, 460)
        window?.close()
        XCTAssertFalse(window?.isVisible == true)
        state.openSettings()
        XCTAssertTrue(state.settingsWindow === window)
        XCTAssertTrue(window?.isVisible == true)
        window?.close()
    }
}
