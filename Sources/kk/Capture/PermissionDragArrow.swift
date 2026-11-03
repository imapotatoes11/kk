import AppKit

/// A solid curved gesture from the draggable app icon toward the app list.
enum PermissionArrowGeometry {
    static func target(in settings: CGRect) -> CGPoint {
        // Aim at the app-list footer, beyond the Settings sidebar.
        CGPoint(x: settings.minX + min(280, settings.width * 0.4), y: settings.minY + 20)
    }

    static func path(from start: CGPoint, to end: CGPoint) -> CGPath {
        let distance = hypot(end.x - start.x, end.y - start.y)
        let bend = min(72, max(32, distance * 0.45))
        let control1 = CGPoint(x: start.x - bend, y: start.y + (end.y - start.y) * 0.25)
        let control2 = CGPoint(x: end.x - bend, y: end.y - (end.y - start.y) * 0.25)
        let path = CGMutablePath()
        path.move(to: start)
        path.addCurve(to: end, control1: control1, control2: control2)
        let angle = atan2(end.y - control2.y, end.x - control2.x)
        for offset: CGFloat in [-.pi / 6, .pi / 6] {
            path.move(to: end)
            path.addLine(to: CGPoint(x: end.x - 12 * cos(angle + offset), y: end.y - 12 * sin(angle + offset)))
        }
        return path
    }
}

@MainActor
final class PermissionDragArrow {
    private(set) var panel: NSPanel?
    func show(from start: CGPoint, to end: CGPoint) {
        let path = PermissionArrowGeometry.path(from: start, to: end)
        let bounds = path.boundingBoxOfPath.insetBy(dx: -8, dy: -8)
        let panel = panel ?? NSPanel(contentRect: bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let view = ArrowView(frame: CGRect(origin: .zero, size: bounds.size))
        var transform = CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)
        view.path = path.copy(using: &transform)
        panel.contentView = view
        panel.setFrame(bounds, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }
    func hide() { panel?.orderOut(nil); panel = nil }
    private final class ArrowView: NSView {
        var path: CGPath?
        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext, let path else { return }
            context.clear(dirtyRect)
            context.setStrokeColor(NSColor.systemRed.withAlphaComponent(0.95).cgColor)
            context.setLineWidth(3)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.addPath(path)
            context.strokePath()
        }
    }
}
