import AppKit
import SwiftUI
import XCTest
@testable import kk

final class PanelPositioningTests: XCTestCase {
    private let visible = NSRect(x: -1920, y: 100, width: 1920, height: 1050)

    func testCursorOpeningIsBelowPointerAndClampsEveryDisplayEdge() {
        for cursor in [NSPoint(x: -1200, y: 800), NSPoint(x: -1920, y: 1150), NSPoint(x: 0, y: 1150), NSPoint(x: -1920, y: 100), NSPoint(x: 0, y: 100)] {
            for size in [NSSize(width: 480, height: 56), NSSize(width: 680, height: 620)] {
                let frame = PanelPositioning.initialFrame(in: visible, contentHeight: size.height, contentWidth: size.width, position: .cursor, cursor: cursor)
                XCTAssertTrue(visible.insetBy(dx: 16, dy: 16).contains(frame), "Cursor openings must remain on screen")
                XCTAssertEqual(frame.size, size)
            }
        }
        let frame = PanelPositioning.initialFrame(in: visible, contentHeight: 56, contentWidth: 480, position: .cursor, cursor: NSPoint(x: -1200, y: 800))
        XCTAssertEqual(frame.midX, -1200)
        XCTAssertEqual(frame.maxY, 788)
        let normal = PanelPositioning.initialFrame(in: visible, contentHeight: 56, contentWidth: 480)
        XCTAssertEqual(normal.midX, visible.midX)
        XCTAssertEqual(normal.maxY, visible.maxY - UIConstants.panelTopMargin)
    }

    func testIndependentSnapAxesAndNonMatchingPositions() {
        for size in [NSSize(width: 480, height: 56), NSSize(width: 680, height: 620)] {
            let target = PanelPositioning.defaultFrame(size: size, in: visible)
            for xOffset: CGFloat in [-10, 10, 80] {
                for yOffset: CGFloat in [-10, 10, 80] {
                    let raw = target.offsetBy(dx: xOffset, dy: yOffset)
                    let snap = PanelPositioning.snapping(raw, in: visible)
                    XCTAssertEqual(snap.snappedX, abs(xOffset) <= 12)
                    XCTAssertEqual(snap.snappedY, abs(yOffset) <= 12)
                    XCTAssertEqual(snap.frame.minX, abs(xOffset) <= 12 ? target.minX : raw.minX)
                    XCTAssertEqual(snap.frame.minY, abs(yOffset) <= 12 ? target.minY : raw.minY)
                    XCTAssertEqual(snap.frame.size, raw.size)
                }
            }
        }
    }

    func testSnapReleaseMarginAvoidsJitterAndAllowsPullingAway() {
        let target = PanelPositioning.defaultFrame(size: NSSize(width: 480, height: 56), in: visible)
        let captured = PanelPositioning.snapping(target.offsetBy(dx: 10, dy: -10), in: visible)
        let retained = PanelPositioning.snapping(target.offsetBy(dx: 18, dy: -18), in: visible, previous: captured)
        XCTAssertTrue(retained.snappedX)
        XCTAssertTrue(retained.snappedY)
        XCTAssertEqual(retained.frame, target)
        let released = PanelPositioning.snapping(target.offsetBy(dx: 25, dy: -25), in: visible, previous: retained)
        XCTAssertFalse(released.snappedX)
        XCTAssertFalse(released.snappedY)
        let outsideCaptureZone = PanelPositioning.snapping(target.offsetBy(dx: 18, dy: -18), in: visible, previous: released)
        XCTAssertFalse(outsideCaptureZone.snappedX)
        XCTAssertFalse(outsideCaptureZone.snappedY)
    }

    @MainActor
    func testNativePopupUsesCursorPreferenceAndGuideLifecycle() async throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.popupOpeningPosition = .cursor
        prefs.popupSize = .compact
        let controller = PanelController(preferences: prefs)
        let screen = try XCTUnwrap(NSScreen.main)
        let cursor = NSPoint(x: screen.visibleFrame.minX + 360, y: screen.visibleFrame.midY)
        controller.show(rootView: AnyView(Color.clear), on: screen, cursorLocation: cursor)
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertEqual(panel.frame.midX, cursor.x, accuracy: 1)
        XCTAssertEqual(panel.frame.maxY, cursor.y - 12, accuracy: 1)
        XCTAssertFalse(controller.alignmentGuidesVisible)
        let target = PanelPositioning.defaultFrame(size: panel.frame.size, in: screen.visibleFrame)
        controller.beginDrag()
        controller.drag(to: target.offsetBy(dx: 8, dy: 50), cursor: NSPoint(x: target.midX, y: target.midY))
        XCTAssertEqual(controller.currentSnap?.snappedX, true)
        XCTAssertEqual(controller.currentSnap?.snappedY, false)
        XCTAssertTrue(controller.alignmentGuidesVisible)
        controller.drag(to: target.offsetBy(dx: 8, dy: -8), cursor: NSPoint(x: target.midX, y: target.midY))
        XCTAssertEqual(panel.frame, target)
        XCTAssertTrue(controller.currentSnap?.snappedY == true)
        controller.endDrag()
        XCTAssertFalse(controller.alignmentGuidesVisible)
        XCTAssertFalse(controller.isDragging)
        XCTAssertEqual(panel.frame, target)

        controller.beginDrag()
        controller.drag(to: target, cursor: NSPoint(x: target.midX, y: target.midY))
        controller.hide()
        XCTAssertFalse(controller.alignmentGuidesVisible)
        XCTAssertFalse(controller.isDragging)
        XCTAssertNil(controller.currentSnap)
    }

    @MainActor
    func testSnapDisabledAndResponseGrowthWaitsForDraggingToEnd() async throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.popupSize = .compact
        prefs.snapToDefaultPosition = false
        let controller = PanelController(preferences: prefs)
        let screen = try XCTUnwrap(NSScreen.main)
        controller.show(rootView: AnyView(Color.clear), on: screen)
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.panel)
        let target = PanelPositioning.defaultFrame(size: panel.frame.size, in: screen.visibleFrame)
        let raw = target.offsetBy(dx: 8, dy: -8)
        controller.beginDrag()
        controller.drag(to: raw, cursor: NSPoint(x: target.midX, y: target.midY))
        XCTAssertEqual(panel.frame, raw)
        XCTAssertFalse(controller.alignmentGuidesVisible)
        controller.updateLayout(hasResponse: true, minimumHeight: 200)
        XCTAssertEqual(panel.frame, raw, "Response layout must not fight the mouse during a drag")
        controller.endDrag()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while controller.isAnimatingLayout && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(panel.frame.width, UIConstants.panelWidth)
        XCTAssertEqual(panel.frame.height, UIConstants.panelMaxHeight)
        XCTAssertEqual(panel.frame.midX, raw.midX, accuracy: 1)
    }
}
