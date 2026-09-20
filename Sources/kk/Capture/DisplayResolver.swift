import AppKit
import CoreGraphics
import ScreenCaptureKit

enum DisplayResolver {
    static func screenContainingMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(point) })
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
