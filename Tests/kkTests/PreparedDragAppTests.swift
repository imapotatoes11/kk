import AppKit
import XCTest
@testable import kk

final class PreparedDragAppTests: XCTestCase {
    @MainActor
    func testFolderAndIconArePreparedOnceBeforeDrawingOrDrag() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kk-drag-" + UUID().uuidString)
        let appURL = root.appendingPathComponent("kk.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var reads: [URL] = []
        var iconLoads = 0
        let source = NSImage(size: NSSize(width: 16, height: 16))
        let prepared = PreparedDragApp.prepare(appURL: appURL, readDirectory: { reads.append($0) }, loadIcon: { _ in iconLoads += 1; return source })
        XCTAssertTrue(prepared.isReady)
        XCTAssertEqual(reads.map(\.path), [root.path])
        XCTAssertEqual(iconLoads, 1)
        XCTAssertFalse(prepared.icon === source)
        let view = AppDragView(appURL: appURL, prepared: prepared)
        view.frame = NSRect(x: 0, y: 0, width: 56, height: 64)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        XCTAssertEqual(reads.count, 1)
        XCTAssertEqual(iconLoads, 1)
        XCTAssertTrue(view.prepared.icon === prepared.icon)
    }

    @MainActor
    func testDeniedFolderAccessDoesNotLoadDragIcon() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("kk-denied-drag-" + UUID().uuidString)
        let appURL = root.appendingPathComponent("kk.app")
        try FileManager.default.createDirectory(at: appURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var iconLoads = 0
        let prepared = PreparedDragApp.prepare(appURL: appURL, readDirectory: { _ in throw CocoaError(.fileReadNoPermission) }, loadIcon: { _ in iconLoads += 1; return NSImage() })
        XCTAssertFalse(prepared.isReady)
        XCTAssertNotNil(prepared.error)
        XCTAssertEqual(iconLoads, 0)
    }

    @MainActor
    func testSuccessfulDropAdvancesHelperButCancellationDoesNot() {
        _ = NSApplication.shared
        let appURL = URL(fileURLWithPath: "/Applications/kk.app")
        let prepared = PreparedDragApp(appURL: appURL, icon: NSImage(), isReady: true, error: nil)
        let helper = PermissionAssistant(accessCheck: { false })
        helper.show(appURL: appURL, prepared: prepared)
        defer { helper.close() }
        let view = AppDragView(appURL: appURL, prepared: prepared)
        view.onDropAccepted = { helper.appWasDropped() }
        view.finishDrag(operation: [])
        XCTAssertFalse(helper.hasAcceptedDrop)
        view.finishDrag(operation: .copy)
        XCTAssertTrue(helper.hasAcceptedDrop)
    }
}
