import AppKit

struct PanelSnapResult: Equatable {
    let frame: NSRect
    let snappedX: Bool
    let snappedY: Bool
}

enum PanelPositioning {
    static let snapDistance: CGFloat = 12
    static let snapReleaseDistance: CGFloat = 20

    /// Preferred automatic layout area. The annotation palette always retains its own strip.
    static func automaticBounds(in visible: NSRect, palette: PalettePosition?, paletteWidth: CGFloat = 680, contentSize: NSSize? = nil) -> NSRect {
        var area = visible.insetBy(dx: 8, dy: 8)
        switch palette {
        case .top: area.size.height -= 56 + 24 + 4
        case .bottom, .popup:
            let reserve: CGFloat = palette == .popup ? 76 : 84
            area.origin.y += reserve
            area.size.height -= reserve
        case .left:
            let reserve = min(paletteWidth, (visible.width - 64) / 2) + 28
            area.origin.x += reserve
            area.size.width -= reserve
        case .right: area.size.width -= min(paletteWidth, (visible.width - 64) / 2) + 28
        case nil: break
        }
        // Spend the edge padding only when those few points let all content fit.
        if let contentSize {
            if contentSize.width > area.width && contentSize.width <= area.width + 16 {
                area.origin.x -= 8
                area.size.width += 16
            }
            if contentSize.height > area.height && contentSize.height <= area.height + 16 {
                area.origin.y -= 8
                area.size.height += 16
            }
        }
        return area
    }

    static func fitted(_ frame: NSRect, size: NSSize, in bounds: NSRect) -> NSRect {
        let size = NSSize(width: min(size.width, bounds.width), height: min(size.height, bounds.height))
        return NSRect(x: min(max(frame.midX - size.width / 2, bounds.minX), bounds.maxX - size.width),
                      y: min(max(frame.midY - size.height / 2, bounds.minY), bounds.maxY - size.height),
                      width: size.width, height: size.height)
    }

    static func initialFrame(on screen: NSScreen, contentHeight: CGFloat = 200, contentWidth: CGFloat = UIConstants.panelWidth, position: PopupOpeningPosition = .defaultPosition, cursor: NSPoint = .zero) -> NSRect {
        initialFrame(in: screen.visibleFrame, contentHeight: contentHeight, contentWidth: contentWidth, position: position, cursor: cursor)
    }

    static func initialFrame(in visible: NSRect, contentHeight: CGFloat, contentWidth: CGFloat, position: PopupOpeningPosition = .defaultPosition, cursor: NSPoint = .zero) -> NSRect {
        let size = NSSize(width: min(contentWidth, visible.width - 32), height: min(contentHeight, max(56, visible.height - 32)))
        if position == .cursor {
            return clamped(NSRect(x: cursor.x - size.width / 2, y: cursor.y - 12 - size.height, width: size.width, height: size.height), in: visible)
        }
        return defaultFrame(size: size, in: visible)
    }

    static func defaultFrame(size: NSSize, in visible: NSRect) -> NSRect {
        clamped(NSRect(x: visible.midX - size.width / 2, y: visible.maxY - UIConstants.panelTopMargin - size.height, width: size.width, height: size.height), in: visible)
    }

    /// Each axis has a small release margin so the window does not flicker in and out of alignment.
    static func snapping(_ frame: NSRect, in visible: NSRect, previous: PanelSnapResult? = nil) -> PanelSnapResult {
        let target = defaultFrame(size: frame.size, in: visible)
        let xDistance = previous?.snappedX == true ? snapReleaseDistance : snapDistance
        let yDistance = previous?.snappedY == true ? snapReleaseDistance : snapDistance
        let snapX = abs(frame.midX - target.midX) <= xDistance
        let snapY = abs(frame.maxY - target.maxY) <= yDistance
        var result = frame
        if snapX { result.origin.x = target.minX }
        if snapY { result.origin.y = target.minY }
        return PanelSnapResult(frame: result, snappedX: snapX, snappedY: snapY)
    }

    static func clamped(_ frame: NSRect, to screen: NSScreen) -> NSRect { clamped(frame, in: screen.visibleFrame) }

    static func clamped(_ frame: NSRect, in visibleFrame: NSRect) -> NSRect {
        let visible = visibleFrame.insetBy(dx: 16, dy: 16)
        var result = frame
        result.size.width = min(result.width, visible.width)
        result.size.height = min(result.height, visible.height)
        result.origin.x = min(max(result.origin.x, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(result.origin.y, visible.minY), visible.maxY - result.height)
        return result
    }
}
