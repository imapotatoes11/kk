import AppKit
import SwiftUI
import XCTest
@testable import kk

final class PermissionAssistantTests: XCTestCase {
    func testDeniedPassiveChecksNeverEnterCapture() async throws {
        let service = ScreenCaptureService(permissionCheck: { false })
        for _ in 0..<5 { let allowed = await service.hasAccess(); XCTAssertFalse(allowed) }
        do { _ = try await service.captureSnapshot(displayID: nil); XCTFail("Denied capture must stop at the passive gate") }
        catch let error as KKError { XCTAssertEqual(error, .screenCapturePermission) }
    }

    @MainActor
    func testDeniedPopupRemainsTextOnlyAcrossRefreshes() async throws {
        _ = NSApplication.shared
        let chat = ChatController(preferences: Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!), keychain: TestKeychain(), captureService: ScreenCaptureService(permissionCheck: { false }), apiClient: OpenAICompatibleClient())
        chat.beginCapture(for: try XCTUnwrap(NSScreen.main))
        for _ in 0..<5 { await chat.refreshScreenAccess(); chat.resumeCaptureIfPermitted() }
        if case .permissionRequired = chat.screenContextState {} else { XCTFail("Passive refresh must remain at permission-required") }
        chat.prompt = "Text only"
        XCTAssertTrue(chat.canSend)
        XCTAssertNil(chat.currentPreviewData)
    }

    func testHelperPositionStaysOnScreenAndPrefersBelowSettings() {
        let visible = CGRect(x: -1800, y: 40, width: 1800, height: 1000)
        let settings = CGRect(x: -1400, y: 400, width: 700, height: 500)
        let size = CGSize(width: 400, height: 112)
        let below = PermissionAssistant.helperFrame(beside: settings, visible: visible, size: size)
        XCTAssertEqual(below.midX, settings.midX)
        XCTAssertEqual(below.maxY, settings.minY - 12)
        for frame in [settings, settings.offsetBy(dx: 1000, dy: -600)] {
            XCTAssertTrue(visible.contains(PermissionAssistant.helperFrame(beside: frame, visible: visible, size: size)))
        }
    }

    @MainActor
    func testDraggableTilePublishesAppFileURLAndCopyOperation() throws {
        _ = NSApplication.shared
        let appURL = URL(fileURLWithPath: "/Applications/kk.app", isDirectory: true)
        let view = AppDragView(appURL: appURL)
        XCTAssertEqual(view.appURL, appURL)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        XCTAssertTrue(pasteboard.writeObjects([appURL as NSURL]))
        XCTAssertEqual(pasteboard.readObjects(forClasses: [NSURL.self])?.first as? URL, appURL)
    }
}


extension PermissionAssistantTests {
    @MainActor
    func testAutomaticReopenWaitsForAccessAndHonorsOptOut() async throws {
        var granted = false
        var launches = 0
        let helper = PermissionAssistant(accessCheck: { granted }, canAutomaticallyReopen: { true })
        helper.onRelaunch = { launches += 1; return true }
        defer { helper.close() }
        helper.show(appURL: URL(fileURLWithPath: "/Applications/kk.app"))
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertEqual(launches, 0)
        granted = true
        for _ in 0..<30 {
            if launches == 1 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(launches, 1)
        XCTAssertNil(helper.panel)
        helper.automaticallyReopen = false
        helper.show(appURL: URL(fileURLWithPath: "/Applications/kk.app"))
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(launches, 1)
        XCTAssertNotNil(helper.panel)
    }
}

extension PermissionAssistantTests {
    @MainActor
    func testPermissionFlowHidesOtherKKWindowsAndPreservesDraft() throws {
        _ = NSApplication.shared
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let app = AppState(preferences: preferences, keychain: TestKeychain())
        app.openSettings()
        app.panelController.show(rootView: AnyView(Color.clear), on: try XCTUnwrap(NSScreen.main))
        app.chat.prompt = "Preserve this draft"
        defer { app.panelController.hide(); app.settingsWindow?.close() }
        app.beginPermissionSetup()
        XCTAssertTrue(app.permissionSetupActive)
        XCTAssertTrue(preferences.permissionSetupPending)
        XCTAssertFalse(app.panelController.isVisible)
        XCTAssertFalse(app.settingsWindow?.isVisible ?? true)
        XCTAssertTrue(app.chat.screenCaptureSuspended)
        app.togglePanel()
        XCTAssertFalse(app.panelController.isVisible)
        app.openSettings()
        XCTAssertFalse(app.settingsWindow?.isVisible ?? true)
        XCTAssertEqual(app.chat.prompt, "Preserve this draft")
        app.endPermissionSetup()
        XCTAssertFalse(app.permissionSetupActive)
        XCTAssertFalse(app.chat.screenCaptureSuspended)
        XCTAssertTrue(app.panelController.isVisible)
        XCTAssertTrue(app.settingsWindow?.isVisible ?? false)
        XCTAssertEqual(app.chat.prompt, "Preserve this draft")
    }
}


extension PermissionAssistantTests {
    @MainActor
    func testAutomaticRestartDoesNotCompeteWithSettings() async throws {
        var returnedToKK = false
        var launches = 0
        let helper = PermissionAssistant(accessCheck: { true }, canAutomaticallyReopen: { returnedToKK })
        helper.onRelaunch = { launches += 1; return true }
        defer { helper.close() }
        helper.show(appURL: URL(fileURLWithPath: "/Applications/kk.app"))
        try await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(launches, 0)
        returnedToKK = true
        for _ in 0..<30 {
            if launches == 1 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(launches, 1)
    }
}
