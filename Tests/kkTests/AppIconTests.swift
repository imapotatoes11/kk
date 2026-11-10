import AppKit
import XCTest
@testable import kk

final class AppIconTests: XCTestCase {
    @MainActor
    func testIconDefaultsToDarkAndPersistsIndependentlyOfWindowAppearance() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.iconStyle, .dark)
        preferences.iconStyle = .light
        preferences.appearance = .dark
        XCTAssertEqual(Preferences(defaults: defaults).iconStyle, .light)
        preferences.resetGeneral()
        XCTAssertEqual(preferences.iconStyle, .light, "Resetting General must not reset an About preference")
        defaults.set("unknown", forKey: "iconStyle")
        XCTAssertEqual(Preferences(defaults: defaults).iconStyle, .dark)
    }

    @MainActor
    func testIconUpdatesRunningAppAndAboutInBothWindowAppearances() async throws {
        let app = NSApplication.shared
        let originalIcon = app.applicationIconImage
        defer { app.applicationIconImage = originalIcon }
        let preferences = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        let state = AppState(preferences: preferences, keychain: TestKeychain())
        let controller = SettingsWindowController(appState: state)
        let window = try XCTUnwrap(controller.window)
        defer { window.close() }
        controller.selectSection(NSToolbarItem(itemIdentifier: .init(SettingsSection.about.rawValue)))
        window.orderFront(nil)
        let light = try XCTUnwrap(AppIconStyle.light.image?.tiffRepresentation)
        let dark = try XCTUnwrap(AppIconStyle.dark.image?.tiffRepresentation)
        XCTAssertNotEqual(light, dark, "Both exported icon variants must be bundled")
        try assertIcon(app.applicationIconImage, style: .dark)
        for appearance in [AppAppearance.light, .dark] {
            preferences.appearance = appearance
            for style in AppIconStyle.allCases {
                preferences.iconStyle = style
                try await Task.sleep(for: .milliseconds(150))
                try assertIcon(app.applicationIconImage, style: style)
                XCTAssertEqual(window.contentView?.bounds.size, NSSize(width: 640, height: 480))
                if let directory = ProcessInfo.processInfo.environment["KK_RENDER_DIR"] {
                    let content = try XCTUnwrap(window.contentView)
                    let view = content.superview ?? content
                    view.layoutSubtreeIfNeeded()
                    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
                    try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to:
                        URL(fileURLWithPath: directory).appendingPathComponent("about-icon-\(style.rawValue)-window-\(appearance.rawValue).png"))
                }
            }
        }
    }

    @MainActor
    private func assertIcon(_ image: NSImage, style: AppIconStyle) throws {
        // AppKit adds/scales representations for the Dock. Compare the rendered
        // background rather than TIFF bytes, which change during that conversion.
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        image.draw(in: NSRect(x: 0, y: 0, width: 64, height: 64))
        let color = try XCTUnwrap(bitmap.colorAt(x: 32, y: 7)?.usingColorSpace(.deviceRGB))
        let brightness = (color.redComponent + color.greenComponent + color.blueComponent) / 3
        if style == .dark { XCTAssertLessThan(brightness, 0.3) }
        else { XCTAssertGreaterThan(brightness, 0.8) }
    }
}
