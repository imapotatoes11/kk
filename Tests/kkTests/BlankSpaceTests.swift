import AppKit
import SwiftUI
import XCTest
@testable import kk

final class BlankSpaceTests: XCTestCase {
    private func image(background: CGFloat, divider: CGFloat? = nil, busyLeft: Bool = false) throws -> CGImage {
        let context = try XCTUnwrap(CGContext(data: nil, width: 960, height: 720,
            bitsPerComponent: 8, bytesPerRow: 960 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(gray: background, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 960, height: 720))
        if let divider {
            context.setFillColor(gray: divider, alpha: 1)
            context.fill(CGRect(x: 481, y: 0, width: 1, height: 720))
            context.fill(CGRect(x: 0, y: 361, width: 960, height: 1))
        }
        if busyLeft {
            context.setFillColor(gray: background > 0.5 ? 0 : 1, alpha: 1)
            for y in stride(from: 0, to: 720, by: 8) {
                context.fill(CGRect(x: 0, y: y, width: 440, height: 2))
            }
        }
        return try XCTUnwrap(context.makeImage())
    }

    func testFaintDividersDoNotSplitBlankSpaceInLightOrDarkMode() throws {
        let bounds = CGRect(x: 0, y: 0, width: 960, height: 720)
        for (background, divider) in [(1.0, 0.82), (0.1, 0.28)] {
            let plain = BlankSpaceFinder.find(in: try image(background: background), screenFrame: bounds, visibleFrame: bounds, near: .zero)
            let divided = BlankSpaceFinder.find(in: try image(background: background, divider: divider), screenFrame: bounds, visibleFrame: bounds, near: .zero)
            XCTAssertEqual(plain, divided)
            XCTAssertEqual(divided?.width, 672)
        }
    }

    func testTextLikeStrokesAreOccupiedAndNegativeDisplayCoordinatesWork() throws {
        let bounds = CGRect(x: -960, y: 300, width: 960, height: 720)
        for background in [0.1, 1.0] {
            let space = try XCTUnwrap(BlankSpaceFinder.find(in: image(background: background, busyLeft: true),
                screenFrame: bounds, visibleFrame: bounds, near: CGPoint(x: -900, y: 600)))
            XCTAssertGreaterThanOrEqual(space.minX, bounds.minX + 440)
            XCTAssertTrue(bounds.insetBy(dx: 24, dy: 24).contains(space))
        }
    }

    func testImageTopMapsToAppKitTop() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 720, height: 720,
            bitsPerComponent: 8, bytesPerRow: 720 * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 720, height: 720))
        context.setFillColor(gray: 0, alpha: 1)
        for y in stride(from: 0, to: 360, by: 8) {
            context.fill(CGRect(x: 0, y: y, width: 720, height: 2))
        }
        let bounds = CGRect(x: 0, y: 0, width: 720, height: 720)
        let space = try XCTUnwrap(BlankSpaceFinder.find(in: XCTUnwrap(context.makeImage()),
            screenFrame: bounds, visibleFrame: bounds, near: .zero))
        XCTAssertGreaterThanOrEqual(space.minY, 360)
    }

    func testFitReducesBothDimensionsAndKeepsComposerUsable() {
        let visible = CGRect(x: 0, y: 0, width: 1400, height: 1000)
        let square = CGRect(x: 500, y: 300, width: 400, height: 400)
        let frame = BlankSpaceFinder.fittedFrame(in: square, desired: CGSize(width: 680, height: 620),
            minimum: CGSize(width: 320, height: 220), visible: visible)
        XCTAssertEqual(frame.size, CGSize(width: 384, height: 384))
        XCTAssertTrue(square.contains(frame))
        let tiny = BlankSpaceFinder.fittedFrame(in: CGRect(x: 1100, y: 700, width: 180, height: 180),
            desired: CGSize(width: 680, height: 620), minimum: CGSize(width: 320, height: 220), visible: visible)
        XCTAssertEqual(tiny.size, CGSize(width: 320, height: 220))
        XCTAssertTrue(visible.insetBy(dx: 16, dy: 16).contains(tiny))
    }

    func testNoUsefulSpaceReturnsNil() {
        XCTAssertNil(BlankSpaceFinder.largestSquare(blank: Array(repeating: false, count: 400),
            columns: 20, rows: 20, cell: 12, bounds: CGRect(x: 0, y: 0, width: 240, height: 240), near: .zero))
    }

    @MainActor
    func testPreferencePersistsAndResets() {
        let name = UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let prefs = Preferences(defaults: defaults)
        XCTAssertFalse(prefs.placeInBlankSpace)
        prefs.placeInBlankSpace = true
        XCTAssertTrue(Preferences(defaults: defaults).placeInBlankSpace)
        prefs.resetCustomization()
        XCTAssertFalse(prefs.placeInBlankSpace)
    }

    @MainActor
    func testPlacementAndGrowthStayInBlankSpaceAndHideCancelsPendingScan() async throws {
        _ = NSApplication.shared
        let bitmap = try image(background: 1, divider: 0.82, busyLeft: true)
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.placeInBlankSpace = true
        let controller = PanelController(preferences: prefs, placementCapture: { _ in
            try await Task.sleep(for: .milliseconds(50))
            return bitmap
        })
        let screen = try XCTUnwrap(NSScreen.main)
        controller.show(rootView: AnyView(Color.clear), on: screen)
        defer { controller.hide() }
        try await Task.sleep(for: .milliseconds(800))
        let panel = try XCTUnwrap(controller.panel)
        let width = panel.frame.width
        XCTAssertLessThanOrEqual(width, prefs.openingWidth)
        let space = try XCTUnwrap(BlankSpaceFinder.find(in: bitmap, screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame, near: CGPoint(x: panel.frame.midX, y: panel.frame.midY)))
        XCTAssertEqual(width, min(prefs.openingWidth, max(320, space.width - 16)), accuracy: 1)
        controller.updateLayout(hasResponse: true, minimumHeight: 220, contentHeight: 620, preferredWidth: 680)
        try await Task.sleep(for: .milliseconds(700))
        XCTAssertEqual(panel.frame.width, width, accuracy: 1)
        XCTAssertTrue(screen.visibleFrame.contains(panel.frame))
        let frame = panel.frame
        controller.moveToBlankSpace()
        controller.hide()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(panel.frame, frame)
        XCTAssertFalse(panel.isVisible)
    }

    @MainActor
    func testCaptureFailureKeepsNormalChatAvailable() async throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.placeInBlankSpace = true
        let controller = PanelController(preferences: prefs, placementCapture: { _ in throw KKError.screenCapturePermission })
        let screen = try XCTUnwrap(NSScreen.main)
        controller.show(rootView: AnyView(Color.clear), on: screen)
        defer { controller.hide() }
        let frame = try XCTUnwrap(controller.panel).frame
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(controller.isVisible)
        XCTAssertEqual(controller.panel?.frame, frame)
    }
}
