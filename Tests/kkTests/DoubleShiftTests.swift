import AppKit
import XCTest
@testable import kk

final class DoubleShiftTests: XCTestCase {
    func testTwoShortShiftTapsTriggerOnce() {
        var detector = DoubleShiftDetector()
        XCTAssertFalse(detector.changed(isDown: true, onlyShift: true, time: 1))
        XCTAssertFalse(detector.changed(isDown: false, onlyShift: true, time: 1.08))
        XCTAssertFalse(detector.changed(isDown: true, onlyShift: true, time: 1.18))
        XCTAssertTrue(detector.changed(isDown: false, onlyShift: true, time: 1.26))
        XCTAssertFalse(detector.changed(isDown: false, onlyShift: true, time: 1.27))
    }
    func testTypingOtherModifiersHoldsAndSlowTapsDoNotTrigger() {
        for interruption in 0..<4 {
            var detector = DoubleShiftDetector()
            _ = detector.changed(isDown: true, onlyShift: true, time: 1)
            _ = detector.changed(isDown: false, onlyShift: true, time: 1.08)
            if interruption == 0 { detector.reset() } // A typed character or click.
            let next = interruption == 1 ? 2.0 : 1.18
            _ = detector.changed(isDown: true, onlyShift: interruption != 2, time: next)
            XCTAssertFalse(detector.changed(isDown: false, onlyShift: true, time: next + (interruption == 3 ? 0.5 : 0.08)))
        }
    }
    @MainActor
    func testReturnPreferencePersistsAndDraftBlocksRestart() async {
        let suite = "kk-return-key-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.annotationReturnKey, .doubleShift)
        preferences.annotationReturnKey = .shortcut
        XCTAssertEqual(Preferences(defaults: defaults).annotationReturnKey, .shortcut)
        let app = AppState(preferences: preferences, keychain: TestKeychain())
        app.chat.prompt = "Keep this draft"
        let restarted = await app.relaunchForPermission()
        XCTAssertFalse(restarted)
        XCTAssertEqual(app.chat.prompt, "Keep this draft")
    }
}
