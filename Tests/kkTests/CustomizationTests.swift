import AppKit
import SwiftUI
import XCTest
@testable import kk

final class CustomizationTests: XCTestCase {
    @MainActor
    func testCustomizationPersistsAndResetPreservesConnection() {
        let suite = "kk-customization-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.popupSize, .fullSize)
        XCTAssertTrue(preferences.alwaysOnTop)
        preferences.baseURL = "https://fixture.invalid/v1"
        preferences.model = "fixture-model"
        preferences.popupSize = .compact
        preferences.popupMaterial = .liquidGlass
        preferences.appearance = .dark
        preferences.accent = .orange
        preferences.alwaysOnTop = false
        preferences.answerTextSize = .large
        preferences.showThinking = true
        preferences.copyShortcutAction = .copyAndClose
        preferences.popupOpeningPosition = .cursor
        preferences.snapToDefaultPosition = false
        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.popupSize, .compact)
        XCTAssertEqual(restored.popupMaterial, .liquidGlass)
        XCTAssertEqual(restored.appearance, .dark)
        XCTAssertEqual(restored.accent, .orange)
        XCTAssertFalse(restored.alwaysOnTop)
        XCTAssertEqual(restored.answerTextSize, .large)
        XCTAssertTrue(restored.showThinking)
        XCTAssertEqual(restored.copyShortcutAction, .copyAndClose)
        XCTAssertEqual(restored.popupOpeningPosition, .cursor)
        XCTAssertFalse(restored.snapToDefaultPosition)
        restored.resetCustomization()
        let reset = Preferences(defaults: defaults)
        XCTAssertEqual(reset.popupSize, .fullSize)
        XCTAssertEqual(reset.popupMaterial, .opaque)
        XCTAssertEqual(reset.appearance, .system)
        XCTAssertEqual(reset.accent, .system)
        XCTAssertTrue(reset.alwaysOnTop)
        XCTAssertEqual(reset.answerTextSize, .standard)
        XCTAssertFalse(reset.showThinking)
        XCTAssertEqual(reset.copyShortcutAction, .copyAndClose)
        XCTAssertEqual(reset.popupOpeningPosition, .defaultPosition)
        XCTAssertTrue(reset.snapToDefaultPosition)
        XCTAssertEqual(reset.baseURL, "https://fixture.invalid/v1")
        XCTAssertEqual(reset.model, "fixture-model")
        defaults.set("unknown-future-material", forKey: "popupMaterial")
        XCTAssertEqual(Preferences(defaults: defaults).popupMaterial, .opaque)
    }

    @MainActor
    func testCompactExpansionAnimatesAndDoesNotRestartForResponseUpdates() async throws {
        _ = NSApplication.shared
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        preferences.popupSize = .compact
        let controller = PanelController(preferences: preferences)
        let screen = try XCTUnwrap(NSScreen.main)
        controller.show(rootView: AnyView(Color.clear), on: screen)
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertEqual(panel.frame.width, UIConstants.compactPanelWidth)
        XCTAssertEqual(panel.frame.height, 56)
        let initial = panel.frame
        controller.updateLayout(hasResponse: true, minimumHeight: 200)
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            XCTAssertTrue(controller.isAnimatingLayout)
            var sawIntermediateFrame = false
            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while controller.isAnimatingLayout && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(16))
                if panel.frame.width > initial.width && panel.frame.width < UIConstants.panelWidth {
                    sawIntermediateFrame = true
                    XCTAssertGreaterThan(panel.frame.height, initial.height)
                    XCTAssertLessThan(panel.frame.height, UIConstants.panelMaxHeight)
                }
                // Response chunks can request layout on every frame without starving completion.
                controller.updateLayout(hasResponse: true, minimumHeight: 220)
            }
            XCTAssertTrue(sawIntermediateFrame, "Expansion must render actual intermediate window sizes")
        }
        XCTAssertFalse(controller.isAnimatingLayout)
        XCTAssertEqual(panel.frame.width, UIConstants.panelWidth)
        XCTAssertEqual(panel.frame.height, UIConstants.panelMaxHeight)
        XCTAssertEqual(panel.frame.maxY, initial.maxY, accuracy: 1)
        XCTAssertEqual(panel.frame.midX, initial.midX, accuracy: 1)
        controller.hide()
        controller.show(rootView: AnyView(Color.clear), on: screen)
        XCTAssertEqual(panel.frame.width, UIConstants.compactPanelWidth)
        XCTAssertEqual(panel.frame.height, 56)
        // Reopening during a transition cancels its old target.
        controller.updateLayout(hasResponse: true, minimumHeight: 200)
        controller.hide()
        controller.show(rootView: AnyView(Color.clear), on: screen)
        try await Task.sleep(for: .milliseconds(350))
        XCTAssertEqual(panel.frame.width, UIConstants.compactPanelWidth)
        XCTAssertEqual(panel.frame.height, 56)
    }

    @MainActor
    func testFullSizeAndLiveWindowPreferences() async throws {
        _ = NSApplication.shared
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let controller = PanelController(preferences: preferences)
        controller.show(rootView: AnyView(Color.clear), on: try XCTUnwrap(NSScreen.main))
        defer { controller.hide() }
        let panel = try XCTUnwrap(controller.panel)
        XCTAssertEqual(panel.frame.width, UIConstants.panelWidth)
        XCTAssertEqual(panel.frame.height, 121)
        XCTAssertEqual(panel.level, .floating)
        preferences.alwaysOnTop = false
        preferences.appearance = .dark
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(panel.level, .normal)
        XCTAssertFalse(panel.isFloatingPanel)
        XCTAssertEqual(panel.appearance?.name, .darkAqua)
        preferences.appearance = .light
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(panel.appearance?.name, .aqua)
        preferences.appearance = .system
        preferences.alwaysOnTop = true
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(panel.appearance)
        XCTAssertEqual(panel.level, .floating)
        preferences.popupSize = .compact
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(panel.frame.width, UIConstants.compactPanelWidth)
        XCTAssertLessThanOrEqual(panel.frame.height, 121)
    }

    @MainActor
    func testSettingsAppearanceUpdatesImmediately() async throws {
        _ = NSApplication.shared
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let app = AppState(preferences: preferences, keychain: TestKeychain())
        app.openSettings()
        defer { app.settingsWindow?.close() }
        preferences.appearance = .dark
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(app.settingsWindow?.appearance?.name, .darkAqua)
        preferences.appearance = .system
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertNil(app.settingsWindow?.appearance)
    }

    @MainActor
    func testPopupMaterialsAndAnswerSizesRender() async throws {
        _ = NSApplication.shared
        for material in PopupMaterial.allCases {
            let host = NSHostingView(rootView: PopupBackground(material: material).frame(width: 480, height: 200))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = host
            window.orderFront(nil)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(100))
            host.layoutSubtreeIfNeeded()
            if material == .translucent {
                let effects = descendants(host).compactMap { $0 as? NSVisualEffectView }
                XCTAssertTrue(effects.contains { $0.blendingMode == .behindWindow && $0.material == .hudWindow })
            }
            if material == .liquidGlass, #available(macOS 26, *) {
                // The public SwiftUI glassEffect renderer controls material activity explicitly.
                XCTAssertFalse(descendants(host).contains { $0 is NSVisualEffectView }, "Glass should not silently fall back to the translucent material")
            }
        }
        let text = String(repeating: "A longer answer with words that wrap naturally. ", count: 12)
        let small = NSHostingView(rootView: ResponseView(markdown: text, isStreaming: false, textSize: AnswerTextSize.small.points).frame(width: 400))
        let large = NSHostingView(rootView: ResponseView(markdown: text, isStreaming: false, textSize: AnswerTextSize.large.points).frame(width: 400))
        XCTAssertGreaterThan(large.fittingSize.height, small.fittingSize.height)
    }

    @MainActor
    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
