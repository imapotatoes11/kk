import AppKit
import XCTest
@testable import kk

final class ColorPanelTests: XCTestCase {
    func testColorPanelPrefersBelowAndFallsBackAboveAtBottomEdge() {
        let visible = CGRect(x: -1800, y: 40, width: 1800, height: 1000)
        let size = CGSize(width: 288, height: 60)
        let anchor = CGRect(x: -900, y: 600, width: 44, height: 48)
        let below = AnnotationColorPanel.frame(anchor: anchor, visible: visible, size: size)
        XCTAssertEqual(below.maxY, anchor.minY - 8)
        let bottom = CGRect(x: -900, y: 50, width: 44, height: 48)
        XCTAssertEqual(AnnotationColorPanel.frame(anchor: bottom, visible: visible, size: size).minY, bottom.maxY + 8)
        let blocked = CGRect(x: -1050, y: 500, width: 480, height: 90)
        XCTAssertEqual(AnnotationColorPanel.frame(anchor: anchor, visible: visible, size: size, avoiding: blocked).minY, anchor.maxY + 8)
        for x in [-1800.0, -900, -1] {
            XCTAssertTrue(visible.contains(AnnotationColorPanel.frame(anchor: CGRect(x: x, y: 50, width: 44, height: 48), visible: visible, size: size)))
        }
    }

    @MainActor
    func testPickerStaysAbovePopupAndClosesCleanly() throws {
        _ = NSApplication.shared
        let source = NSPanel(contentRect: CGRect(x: 100, y: 300, width: 480, height: 56), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        source.isReleasedWhenClosed = false
        source.level = NSWindow.Level(rawValue: 4)
        let button = NSButton(frame: CGRect(x: 200, y: 4, width: 44, height: 48))
        source.contentView?.addSubview(button)
        source.orderFrontRegardless()
        let popup = NSPanel(contentRect: CGRect(x: 100, y: 370, width: 480, height: 56), styleMask: [.borderless], backing: .buffered, defer: false)
        popup.isReleasedWhenClosed = false; popup.level = NSWindow.Level(rawValue: 5); popup.orderFrontRegardless()
        let controller = AnnotationColorPanel()
        controller.popup = popup
        defer { controller.close(); source.close(); popup.close() }
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        controller.toggle(from: button, preferences: preferences, onSelection: {})
        let picker = try XCTUnwrap(controller.panel)
        XCTAssertGreaterThan(picker.level.rawValue, popup.level.rawValue)
        XCTAssertLessThan(picker.frame.maxY, source.frame.minY)
        XCTAssertTrue(controller.isVisible)
        controller.toggle(from: button, preferences: preferences, onSelection: {})
        XCTAssertFalse(controller.isVisible)
        XCTAssertFalse(picker.isVisible)
    }

    func testAskCornerRadiusUsesOuterMinusInset() {
        XCTAssertEqual(PopupGeometry.actionRadius, 18)
        XCTAssertEqual(PopupGeometry.actionRadius + PopupGeometry.palettePadding, PopupGeometry.cornerRadius)
        XCTAssertEqual(PopupGeometry.actionHeight + 2 * PopupGeometry.palettePadding, 56)
    }
}
