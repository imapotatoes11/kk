import AppKit
import XCTest
@testable import kk

final class SettingsWindowTests: XCTestCase {
    @MainActor
    func testSettingsWindowOpensAndCanReopen() {
        _ = NSApplication.shared
        let state = AppState(preferences: Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!), keychain: TestKeychain())
        state.openSettings()
        let window = state.settingsWindow
        XCTAssertNotNil(window)
        XCTAssertEqual(window?.title, "kk Settings")
        XCTAssertTrue(window?.isVisible == true)
        XCTAssertGreaterThanOrEqual(window?.contentView?.bounds.height ?? 0, 300)
        XCTAssertGreaterThanOrEqual(window?.contentView?.bounds.width ?? 0, 460)
        XCTAssertEqual(window?.toolbar?.displayMode, .iconAndLabel)
        XCTAssertEqual(window?.toolbar?.items.filter { $0.itemIdentifier != .flexibleSpace }.map(\.label), ["Connection", "Customization", "Shortcuts", "About"])
        window?.close()
        XCTAssertFalse(window?.isVisible == true)
        state.openSettings()
        XCTAssertTrue(state.settingsWindow === window)
        XCTAssertTrue(window?.isVisible == true)
        window?.close()
    }
}

struct TestKeychain: APIKeyStoring {
    func loadAPIKey() -> String? { nil }
    func saveAPIKey(_ value: String) throws {}
    func deleteAPIKey() throws {}
}

extension SettingsWindowTests {
    @MainActor
    func testSettingsTabsRenderAndRememberSelection() async throws {
        _ = NSApplication.shared
        let state = AppState(preferences: Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!), keychain: TestKeychain())
        let controller = SettingsWindowController(appState: state)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        window.orderFront(nil)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            state.preferences.appearance = appearance == .aqua ? .light : .dark
            for section in SettingsSection.allCases {
                controller.selectSection(NSToolbarItem(itemIdentifier: .init(section.rawValue)))
                try await Task.sleep(for: .milliseconds(200))
                XCTAssertEqual(controller.selection.section, section)
                XCTAssertEqual(window.toolbar?.selectedItemIdentifier?.rawValue, section.rawValue)
                let content = try XCTUnwrap(window.contentView)
                content.layoutSubtreeIfNeeded()
                if let directory = ProcessInfo.processInfo.environment["KK_RENDER_DIR"] {
                    let view = content.superview ?? content
                    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    let name = "settings-\(section.rawValue)-\(appearance == .aqua ? "light" : "dark").png"
                    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                    try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent(name))
                }
            }
        }
        window.close()
        window.orderFront(nil)
        XCTAssertEqual(controller.selection.section, .about)
    }
}
