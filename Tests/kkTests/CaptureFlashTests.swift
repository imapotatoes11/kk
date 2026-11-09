import AppKit
import XCTest
@testable import kk

final class CaptureFlashTests: XCTestCase {
    @MainActor
    func testPreferencePersistsAndGeneralResetTurnsFlashOff() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.captureFlash, .off)
        prefs.captureFlash = .low
        XCTAssertEqual(Preferences(defaults: defaults).captureFlash, .low)
        prefs.resetAdvanced()
        XCTAssertEqual(prefs.captureFlash, .low)
        prefs.resetGeneral()
        XCTAssertEqual(prefs.captureFlash, .off)
    }

    @MainActor
    func testFlashIsNoninteractiveOnCapturedDisplayAndCleansUp() async throws {
        _ = NSApplication.shared
        let controller = CaptureFlashController()
        defer { controller.cancel() }
        let screen = try XCTUnwrap(NSScreen.main)
        let id = try XCTUnwrap(DisplayResolver.displayID(for: screen))
        let keyWindow = NSApp.keyWindow
        controller.flash(displayID: id, mode: .off)
        XCTAssertTrue(controller.panels.isEmpty)
        controller.flash(displayID: id, mode: .low)
        let panel = try XCTUnwrap(controller.panels[id])
        XCTAssertEqual(panel.frame, screen.frame)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertTrue(NSApp.keyWindow === keyWindow)
        XCTAssertEqual(panel.sharingType, .none)
        XCTAssertLessThanOrEqual(panel.alphaValue, 0.25)
        controller.flash(displayID: id, mode: .low)
        let replacement = try XCTUnwrap(controller.panels[id])
        XCTAssertFalse(replacement === panel)
        XCTAssertFalse(panel.isVisible)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertTrue(controller.panels.isEmpty)
        XCTAssertFalse(replacement.isVisible)
    }

    @MainActor
    func testFeedbackFiresOnceAfterSuccessfulCaptureNeverForFailureOrRetryAttempt() async throws {
        let probe = FlashCaptureProbe()
        var displays: [CGDirectDisplayID?] = []
        let service = ScreenCaptureService(permissionCheck: { true }, captureAttempt: { try await probe.capture($0) },
            onCaptureCompleted: { displays.append($0) }, retryDelay: .zero)
        _ = try await service.captureSnapshot(displayID: 42)
        XCTAssertEqual(displays, [42])
        let count = await probe.count
        XCTAssertEqual(count, 2)
        let denied = ScreenCaptureService(permissionCheck: { false }, onCaptureCompleted: { displays.append($0) })
        do { _ = try await denied.captureSnapshot(displayID: 99); XCTFail("Must fail") } catch {}
        XCTAssertEqual(displays, [42])
    }
}

private actor FlashCaptureProbe {
    var count = 0
    func capture(_ id: CGDirectDisplayID?) throws -> ScreenSnapshot {
        count += 1
        if count == 1 { throw ScreenCaptureAttemptError.selfExclusionUnavailable }
        let context = try XCTUnwrap(CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return ScreenSnapshot(image: try XCTUnwrap(context.makeImage()), data: Data([1]))
    }
}
