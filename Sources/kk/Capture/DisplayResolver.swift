import AppKit
import CoreGraphics
import ScreenCaptureKit

enum DisplayResolver {
    static func screenContainingMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(point) })
    }

    /// Window geometry only, without Accessibility permission or reading window contents.
    static func activeWindowFrame() -> CGRect? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return NSApp.keyWindow?.frame }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier { return NSApp.keyWindow?.frame }
        guard let primary = NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in windows where (info[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier && (info[kCGWindowLayer as String] as? Int) == 0 {
            if let bounds = info[kCGWindowBounds as String] as? NSDictionary,
               let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 0, rect.height > 0 {
                return CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
            }
        }
        return nil
    }

    static func captureScreens(mode: CaptureDisplayMode) -> [NSScreen] {
        let screens = NSScreen.screens
        let indices = selectedIndices(mode: mode, frames: screens.map(\.frame), cursor: NSEvent.mouseLocation,
                                      activeWindow: activeWindowFrame(), fallback: screens.firstIndex(where: { $0 === NSScreen.main }) ?? 0)
        var seen: Set<CGDirectDisplayID> = []
        return indices.compactMap { index in
            let screen = screens[index]
            guard let id = displayID(for: screen), seen.insert(id).inserted else { return nil }
            return screen
        }
    }

    /// All-display capture starts with the pointer's display, where drawing will happen.
    static func selectedIndices(mode: CaptureDisplayMode, frames: [CGRect], cursor: CGPoint, activeWindow: CGRect?, fallback: Int = 0) -> [Int] {
        guard !frames.isEmpty else { return [] }
        let fallback = frames.indices.contains(fallback) ? fallback : 0
        let cursorIndex = frames.firstIndex(where: { $0.contains(cursor) }) ?? fallback
        switch mode {
        case .cursor: return [cursorIndex]
        case .all: return [cursorIndex] + frames.indices.filter { $0 != cursorIndex }
        case .active:
            guard let activeWindow else { return [fallback] }
            let overlaps = frames.map { frame -> CGFloat in
                let overlap = frame.intersection(activeWindow)
                return overlap.isNull ? 0 : overlap.width * overlap.height
            }
            let best = overlaps.indices.max(by: { overlaps[$0] < overlaps[$1] }) ?? fallback
            return [overlaps[best] > 0 ? best : fallback]
        }
    }

    static func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? CGDirectDisplayID
    }

    static func display(in content: SCShareableContent, matching screen: NSScreen) -> SCDisplay? {
        guard let id = displayID(for: screen) else { return content.displays.first }
        return content.displays.first(where: { $0.displayID == id }) ?? content.displays.first
    }
}
