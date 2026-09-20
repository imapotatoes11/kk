import AppKit

enum PanelPositioning {
    static func initialFrame(on screen: NSScreen, contentHeight: CGFloat = 132) -> NSRect {
        let visible = screen.visibleFrame
        let width = min(UIConstants.panelWidth, max(320, visible.width - 32))
        let height = min(contentHeight, max(160, visible.height - 120))
        let x = visible.midX - width / 2
        let top = min(visible.maxY - 24, visible.maxY - UIConstants.panelTopMargin)
        let y = max(visible.minY + 16, top - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }

    static func clamped(_ frame: NSRect, to screen: NSScreen) -> NSRect {
        let visible = screen.visibleFrame.insetBy(dx: 16, dy: 16)
        var result = frame
        result.size.width = min(result.width, visible.width)
        result.size.height = min(result.height, visible.height)
        result.origin.x = min(max(result.origin.x, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.origin.y, visible.minY), visible.maxY - result.height)
        return result
    }
}
