import AppKit
import SwiftUI
import XCTest
@testable import kk

final class ExpandToFitTests: XCTestCase {
    func testAutomaticBoundsReserveEveryPalettePositionOnOffsetDisplay() {
        let visible = NSRect(x: -1512, y: 80, width: 1512, height: 900)
        for position in PalettePosition.allCases {
            let bounds = PanelPositioning.automaticBounds(in: visible, palette: position, paletteWidth: 480)
            let chat = PanelPositioning.fitted(bounds, size: bounds.size, in: bounds)
            let width = position == .left || position == .right ? min(480, (visible.width - 64) / 2) : chat.width
            let palette = position.frame(in: visible, size: NSSize(width: width, height: 56), popup: chat)
            XCTAssertFalse(chat.intersects(palette), "\(position) must not cover annotations")
            XCTAssertTrue(visible.contains(chat))
        }
    }

    func testEdgePaddingIsUsedOnlyWhenItLetsContentFit() {
        let visible = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let padded = PanelPositioning.automaticBounds(in: visible, palette: nil)
        XCTAssertEqual(padded, visible.insetBy(dx: 8, dy: 8))
        XCTAssertEqual(PanelPositioning.automaticBounds(in: visible, palette: nil,
            contentSize: NSSize(width: 995, height: 795)), visible)
        XCTAssertEqual(PanelPositioning.automaticBounds(in: visible, palette: nil,
            contentSize: NSSize(width: 2000, height: 2000)), padded)
    }

    @MainActor
    func testWidthPercentageDefaultsClampsPersistsAndResets() async throws {
        _ = NSApplication.shared
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.expandWidthPercent, 40)
        let controller = PanelController(preferences: prefs)
        let screen = try XCTUnwrap(NSScreen.main)
        controller.show(rootView: AnyView(Color.clear), on: screen)
        defer { controller.hide() }
        controller.updateLayout(hasResponse: true, minimumHeight: 220, contentHeight: 5000, preferredWidth: 5000)
        for percent in [20, 40, 60] {
            prefs.expandWidthPercent = percent
            controller.expandToFit()
            try await Task.sleep(for: .milliseconds(650))
            XCTAssertLessThanOrEqual(try XCTUnwrap(controller.panel).frame.width, floor(screen.frame.width * CGFloat(percent) / 100), "Absolute cap, even below the normal minimum width")
            XCTAssertEqual(Preferences(defaults: defaults).expandWidthPercent, percent)
        }
        prefs.expandWidthPercent = 100
        XCTAssertEqual(prefs.expandWidthPercent, 60)
        prefs.expandWidthPercent = 0
        XCTAssertEqual(prefs.expandWidthPercent, 20)
        defaults.set(500, forKey: "expandWidthPercent")
        XCTAssertEqual(Preferences(defaults: defaults).expandWidthPercent, 60)
        prefs.resetAdvanced()
        XCTAssertEqual(prefs.expandWidthPercent, 40)
    }

    func testPaletteUsesSmallGapBelowBeforeCoveringChatHeader() {
        let visible = NSRect(x: -1512, y: 80, width: 1512, height: 900)
        let popup = NSRect(x: -1000, y: visible.minY + 68, width: 600, height: visible.height - 88)
        for position in [PalettePosition.popup, .top] {
            let palette = position.frame(in: visible, size: NSSize(width: 600, height: 56), popup: popup)
            XCTAssertTrue(visible.contains(palette))
            XCTAssertLessThanOrEqual(palette.maxY, popup.minY)
            XCTAssertFalse(palette.intersects(popup))
        }
        let noVerticalRoom = NSRect(x: -900, y: visible.minY, width: 500, height: visible.height)
        let palette = PalettePosition.popup.frame(in: visible, size: NSSize(width: 480, height: 56), popup: noVerticalRoom)
        XCTAssertFalse(palette.intersects(noVerticalRoom), "Use a free side when neither above nor below fits")
    }

    func testCenteredExpansionUsesBothDirectionsAndClampsAtEdges() {
        let bounds = NSRect(x: -1500, y: 90, width: 1480, height: 880)
        let original = NSRect(x: -1000, y: 400, width: 400, height: 200)
        let expanded = PanelPositioning.fitted(original, size: NSSize(width: 800, height: 600), in: bounds)
        XCTAssertEqual(expanded.midX, original.midX)
        XCTAssertEqual(expanded.midY, original.midY)
        XCTAssertLessThan(expanded.minX, original.minX)
        XCTAssertGreaterThan(expanded.maxX, original.maxX)
        XCTAssertLessThan(expanded.minY, original.minY)
        XCTAssertGreaterThan(expanded.maxY, original.maxY)
        XCTAssertEqual(PanelPositioning.fitted(original, size: NSSize(width: 4000, height: 4000), in: bounds), bounds)
    }

    @MainActor
    func testShortcutDefaultsPersistenceExpansionAndManualOverride() async throws {
        _ = NSApplication.shared
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let prefs = Preferences(defaults: defaults)
        XCTAssertNil(prefs.windowBindings["expand"])
        prefs.windowBindings["expand"] = .init(keyCode: 3, modifiers: NSEvent.ModifierFlags.command.rawValue, label: "⌘F")
        XCTAssertEqual(Preferences(defaults: defaults).windowBindings, prefs.windowBindings)
        let controller = PanelController(preferences: prefs)
        let screen = try XCTUnwrap(NSScreen.main)
        controller.show(rootView: AnyView(Color.clear), on: screen)
        defer { controller.hide() }
        controller.annotationLayerActive = true
        controller.updateLayout(hasResponse: true, minimumHeight: 220, contentHeight: 5000, preferredWidth: 5000)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
            timestamp: 0, windowNumber: try XCTUnwrap(controller.panel).windowNumber, context: nil,
            characters: "f", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3))
        controller.panel?.sendEvent(event)
        XCTAssertTrue(controller.expandsToFit, "The configured key must dispatch inside the chat window")
        try await Task.sleep(for: .milliseconds(700))
        let panel = try XCTUnwrap(controller.panel)
        let bounds = PanelPositioning.automaticBounds(in: screen.visibleFrame, palette: prefs.palettePosition)
        XCTAssertEqual(panel.frame.width, floor(screen.frame.width * 0.4), accuracy: 1)
        XCTAssertEqual(panel.frame.height, bounds.height, accuracy: 1)
        controller.windowWillStartLiveResize(Notification(name: NSWindow.willStartLiveResizeNotification, object: panel))
        let manual = NSRect(x: bounds.minX, y: screen.visibleFrame.maxY - 500, width: 500, height: 500)
        panel.setFrame(manual, display: false)
        controller.updateLayout(hasResponse: true, minimumHeight: 220, contentHeight: 5000, preferredWidth: 5000)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(panel.frame, manual, "Streaming must preserve a manual overlap")
        XCTAssertFalse(controller.expandsToFit)
    }
}
