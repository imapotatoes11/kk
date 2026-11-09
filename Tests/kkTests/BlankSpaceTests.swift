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

    private func grid(columns: Int, rows: Int, bounds: CGRect, blank: (Int, Int) -> Bool) -> BlankMap {
        var cells = [Bool](repeating: false, count: columns * rows)
        for row in 0..<rows { for column in 0..<columns { cells[row * columns + column] = blank(row, column) } }
        return BlankMap(columns: columns, rows: rows, cell: 12, bounds: bounds, blank: cells)
    }

    func testFaintDividersDoNotSplitBlankSpaceInLightOrDarkMode() throws {
        let bounds = CGRect(x: 0, y: 0, width: 960, height: 720)
        for (background, divider) in [(1.0, 0.82), (0.1, 0.28)] {
            let plain = try XCTUnwrap(BlankSpaceFinder.map(from: image(background: background), screenFrame: bounds, visibleFrame: bounds))
            let divided = try XCTUnwrap(BlankSpaceFinder.map(from: image(background: background, divider: divider), screenFrame: bounds, visibleFrame: bounds))
            XCTAssertEqual(plain.blank, divided.blank)
            XCTAssertEqual(divided.blankFraction(divided.bounds), 1)
        }
    }

    func testTallerQuietColumnWinsAcrossSurfaceBoundary() throws {
        // Like the reference: short, perfectly flat space at upper right;
        // a much taller empty sidebar/page margin at lower left.
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 960)
        let map = grid(columns: 100, rows: 80, bounds: bounds) { row, column in
            if column >= 60 && row < 31 { return true }
            if column < 36 && row >= 30 { return column != 18 }
            return false
        }
        let spot = BlankSpaceFinder.placement(of: CGSize(width: 400, height: 360), in: map,
            region: bounds, avoiding: nil, near: CGPoint(x: 1000, y: 800))
        XCTAssertLessThan(spot.maxX, 440)
        XCTAssertLessThan(spot.maxY, 610)
        XCTAssertGreaterThan(BlankSpaceFinder.expanded(spot, in: map, region: bounds, minimumHeight: 220).height, 550)
    }

    func testTwoFlatSurfacesAndBorderAreQuietInLightAndDarkMode() throws {
        let bounds = CGRect(x: 0, y: 0, width: 960, height: 720)
        for (background, sidebar) in [(1.0, 0.80), (0.1, 0.30)] {
            let context = try XCTUnwrap(CGContext(data: nil, width: 960, height: 720,
                bitsPerComponent: 8, bytesPerRow: 960 * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(gray: background, alpha: 1)
            context.fill(bounds)
            context.setFillColor(gray: sidebar, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 486, height: 720))
            context.setFillColor(gray: (background + sidebar) / 2, alpha: 1)
            context.fill(CGRect(x: 486, y: 0, width: 1, height: 720))
            let map = try XCTUnwrap(BlankSpaceFinder.map(from: XCTUnwrap(context.makeImage()), screenFrame: bounds, visibleFrame: bounds))
            XCTAssertEqual(map.blankFraction(map.bounds), 1, "A broad color change and thin border must not split empty surfaces")
        }
    }

    func testTextLikeStrokesAreOccupiedAndNegativeDisplayCoordinatesWork() throws {
        let bounds = CGRect(x: -960, y: 300, width: 960, height: 720)
        for background in [0.1, 1.0] {
            let map = try XCTUnwrap(BlankSpaceFinder.map(from: image(background: background, busyLeft: true), screenFrame: bounds, visibleFrame: bounds))
            let spot = BlankSpaceFinder.placement(of: CGSize(width: 400, height: 300), in: map, region: map.bounds,
                avoiding: nil, near: CGPoint(x: -900, y: 600))
            XCTAssertGreaterThanOrEqual(spot.minX, bounds.minX + 440)
            XCTAssertTrue(bounds.insetBy(dx: 24, dy: 24).contains(spot))
            XCTAssertEqual(map.blankFraction(spot), 1)
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
        let map = try XCTUnwrap(BlankSpaceFinder.map(from: XCTUnwrap(context.makeImage()), screenFrame: bounds, visibleFrame: bounds))
        let spot = BlankSpaceFinder.placement(of: CGSize(width: 300, height: 200), in: map, region: map.bounds, avoiding: nil, near: .zero)
        XCTAssertGreaterThanOrEqual(spot.minY, 360)
    }

    func testAllowedRegionKeepsChatBesideTheFocusedWindow() {
        let bounds = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let minimum = CGSize(width: 320, height: 220)
        // A window on the right leaves the left side, like System Settings in the bug report.
        let right = BlankSpaceFinder.allowedRegion(in: bounds, avoiding: CGRect(x: 820, y: 100, width: 700, height: 800), minimum: minimum)
        XCTAssertEqual(right, CGRect(x: 0, y: 0, width: 812, height: 1000))
        // A short, wide window leaves the larger strip above or below it.
        let low = BlankSpaceFinder.allowedRegion(in: bounds, avoiding: CGRect(x: 0, y: 0, width: 1600, height: 400), minimum: minimum)
        XCTAssertEqual(low, CGRect(x: 0, y: 408, width: 1600, height: 592))
        // No room beside a full-screen window, or no focused window: the whole display.
        XCTAssertEqual(BlankSpaceFinder.allowedRegion(in: bounds, avoiding: CGRect(x: 100, y: 50, width: 1450, height: 900), minimum: minimum), bounds)
        XCTAssertEqual(BlankSpaceFinder.allowedRegion(in: bounds, avoiding: nil, minimum: minimum), bounds)
        XCTAssertEqual(BlankSpaceFinder.allowedRegion(in: bounds, avoiding: CGRect(x: 3000, y: 0, width: 500, height: 500), minimum: minimum), bounds,
                       "A window on another display doesn't restrict this one")
    }

    func testFullSizeChatGoesBesideWindowEvenWhenTheQuietSpotIsSmall() {
        // Quiet only in a small patch on the left; the focused window is on the right.
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 960)
        let map = grid(columns: 100, rows: 80, bounds: bounds) { row, column in (10..<30).contains(row) && (5..<25).contains(column) }
        let window = CGRect(x: 760, y: 0, width: 440, height: 960)
        let region = BlankSpaceFinder.allowedRegion(in: bounds, avoiding: window, minimum: CGSize(width: 320, height: 220))
        let spot = BlankSpaceFinder.placement(of: CGSize(width: 680, height: 360), in: map, region: region, avoiding: window, near: CGPoint(x: 600, y: 480))
        XCTAssertEqual(spot.width, 680, "Chat keeps its normal width instead of shrinking to the quiet patch")
        XCTAssertLessThanOrEqual(spot.maxX, window.minX)
        XCTAssertTrue(spot.intersects(CGRect(x: 60, y: 600, width: 240, height: 240)), "It still sits over the quietest area")
    }

    func testOverlapWithFocusedWindowIsPenalizedWhenItCantBeAvoided() {
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 960)
        let map = grid(columns: 100, rows: 80, bounds: bounds) { _, _ in true }
        let window = CGRect(x: 0, y: 0, width: 900, height: 960)
        let spot = BlankSpaceFinder.placement(of: CGSize(width: 400, height: 300), in: map, region: bounds, avoiding: window, near: CGPoint(x: 100, y: 100))
        XCTAssertGreaterThanOrEqual(spot.minX, window.maxX - 100, "Prefers the uncovered strip despite being farther from the preferred point")
    }

    func testSentChatGrowsThroughMostlyQuietRows() throws {
        let columns = 80, rows = 80
        let bounds = CGRect(x: -960, y: 300, width: 960, height: 960)
        // A quiet column from row 5 to 74, except a few icons in row 20 (like a tab strip).
        let map = grid(columns: columns, rows: rows, bounds: bounds) { row, column in
            guard (5..<75).contains(row) && (30..<60).contains(column) else { return false }
            return !(row == 20 && column < 33)
        }
        let start = CGRect(x: bounds.minX + 360, y: bounds.maxY - 600, width: 360, height: 220)
        let frame = BlankSpaceFinder.expanded(start, in: map, region: map.bounds, minimumHeight: 220)
        XCTAssertEqual(frame.maxY, bounds.maxY - 60 - BlankSpaceFinder.margin, "Grows up past the sparse row to the column's top")
        XCTAssertEqual(frame.minY, bounds.minY + 60 + BlankSpaceFinder.margin)
        XCTAssertGreaterThan(frame.height, UIConstants.panelMaxHeight, "Blank-space height may exceed the usual 620-point cap")
        XCTAssertEqual(frame.width, start.width)

        let busy = grid(columns: columns, rows: rows, bounds: bounds) { _, _ in false }
        XCTAssertEqual(BlankSpaceFinder.expanded(start, in: busy, region: busy.bounds, minimumHeight: 220).height, 220, "Never below the minimum")
    }

    @MainActor
    func testPanelGrowsOnlyAsContentArrivesInBothPlacementModes() async throws {
        _ = NSApplication.shared
        let bitmap = try image(background: 1)
        for quiet in [false, true] {
            let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
            prefs.placeInBlankSpace = quiet
            let controller = PanelController(preferences: prefs, placementCapture: { _ in bitmap })
            let screen = try XCTUnwrap(NSScreen.main)
            controller.show(rootView: AnyView(Color.clear), on: screen)
            defer { controller.hide() }
            let panel = try XCTUnwrap(controller.panel)
            try await settle(panel, placed: quiet ? controller : nil)
            controller.updateLayout(hasResponse: true, minimumHeight: 220, contentHeight: 260, preferredWidth: 680, streaming: true)
            try await settle(panel)
            XCTAssertEqual(panel.frame.height, 260, accuracy: 2, "A short answer must not consume the available column")
            controller.updateLayout(hasResponse: true, minimumHeight: 220, contentHeight: 430, preferredWidth: 680, streaming: true)
            try await settle(panel)
            XCTAssertEqual(panel.frame.height, 430, accuracy: 2)
            controller.updateLayout(hasResponse: true, minimumHeight: 220, contentHeight: 1500, preferredWidth: 680, streaming: true)
            try await settle(panel)
            XCTAssertLessThanOrEqual(panel.frame.height, quiet ? screen.visibleFrame.height - 32 : UIConstants.panelMaxHeight)
            XCTAssertGreaterThanOrEqual(panel.frame.height, 430)
        }
    }

    /// Scans take a moment in debug builds; wait until the panel stops moving.
    @MainActor
    private func settle(_ panel: NSPanel, placed controller: PanelController? = nil) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(6))
        if let controller {
            while !controller.hasBlankPlacement && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
            XCTAssertTrue(controller.hasBlankPlacement, "The blank-space scan finished")
        }
        var last = panel.frame
        var stable = 0
        while ContinuousClock.now < deadline && stable < 6 {
            try await Task.sleep(for: .milliseconds(100))
            stable = panel.frame == last ? stable + 1 : 0
            last = panel.frame
        }
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
        let panel = try XCTUnwrap(controller.panel)
        try await settle(panel, placed: controller)
        let map = try XCTUnwrap(BlankSpaceFinder.map(from: bitmap, screenFrame: screen.frame, visibleFrame: screen.visibleFrame))
        XCTAssertEqual(panel.frame.width, min(prefs.openingWidth, screen.visibleFrame.width - 32), accuracy: 1)
        XCTAssertGreaterThanOrEqual(panel.frame.minX, screen.frame.minX + screen.frame.width * 440 / 960 - 1, "Avoids the busy left side")
        controller.updateLayout(hasResponse: true, minimumHeight: 220, contentHeight: 620, preferredWidth: 680)
        try await settle(panel)
        XCTAssertEqual(panel.frame.height, min(620, map.bounds.height - 2 * BlankSpaceFinder.margin), accuracy: 13, "Uses only the height the answer needs")
        XCTAssertTrue(screen.visibleFrame.contains(panel.frame))
        let frame = panel.frame
        controller.beginDrag()
        controller.endDrag()
        XCTAssertEqual(panel.frame, frame, "Taking manual control must preserve the taller fitted window")
        controller.moveToBlankSpace()
        controller.hide()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(panel.frame, frame)
        XCTAssertFalse(panel.isVisible)
    }

    @MainActor
    func testPlacementStaysBesideTheFocusedWindow() async throws {
        _ = NSApplication.shared
        let bitmap = try image(background: 1, busyLeft: true)
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.placeInBlankSpace = true
        prefs.fullWidthLevel = 0
        let controller = PanelController(preferences: prefs, placementCapture: { _ in bitmap })
        let screen = try XCTUnwrap(NSScreen.main)
        let visible = screen.visibleFrame
        // The focused window covers the quiet right side, so kk goes left even though it's busy.
        let window = CGRect(x: visible.midX, y: visible.minY, width: visible.width / 2, height: visible.height)
        controller.avoidedWindowFrame = window
        controller.show(rootView: AnyView(Color.clear), on: screen)
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.panel)
        try await settle(panel, placed: controller)
        XCTAssertLessThanOrEqual(panel.frame.maxX, window.minX + 1)
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
