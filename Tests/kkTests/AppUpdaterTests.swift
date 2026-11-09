import XCTest
@testable import kk

final class AppUpdaterTests: XCTestCase {
    func testVersionUsesInstalledBundleMetadata() {
        XCTAssertEqual(AppVersion(info: ["CFBundleShortVersionString": "0.9.2", "CFBundleVersion": "920"]).description, "Version 0.9.2 (920)")
        XCTAssertEqual(AppVersion(info: ["CFBundleShortVersionString": "1.0"]).description, "Version 1.0")
        XCTAssertEqual(AppVersion(info: [:]).description, "Development build")
    }

    @MainActor
    func testPackageRunnerDoesNotStartAnUpdaterOrCheckTheNetwork() {
        let updater = AppUpdater()
        XCTAssertFalse(updater.isAvailable)
        XCTAssertFalse(updater.canCheckForUpdates)
        XCTAssertNotNil(updater.unavailableReason)
        updater.checkForUpdates()
        XCTAssertNil(updater.lastCheck)
    }
}
