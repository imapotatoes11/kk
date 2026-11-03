import AppKit

@MainActor
final class PermissionDragArrow {
    private var panel: NSPanel?
    func show(from start: CGPoint, to end: CGPoint) {
        let bounds = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: max(1, abs(start.x - end.x)), height: max(1, abs(start.y - end.y))).insetBy(dx: -24, dy: -24)
        let panel = panel ?? NSPanel(contentRect: bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let view = ArrowView(frame: CGRect(origin: .zero, size: bounds.size))
        view.start = CGPoint(x: start.x - bounds.minX, y: start.y - bounds.minY)
        view.end = CGPoint(x: end.x - bounds.minX, y: end.y - bounds.minY)
        panel.contentView = view
        panel.setFrame(bounds, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }
    func hide() { panel?.orderOut(nil); panel = nil }
    private final class ArrowView: NSView {
        var start = CGPoint.zero
        var end = CGPoint.zero
        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            context.clear(dirtyRect)
            context.setStrokeColor(NSColor.systemBlue.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(2.5)
            context.setLineCap(.round)
            context.setLineDash(phase: 0, lengths: [5, 5])
            context.move(to: start); context.addLine(to: end); context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            let angle = atan2(end.y - start.y, end.x - start.x)
            for offset: CGFloat in [-.pi / 6, .pi / 6] {
                context.move(to: end)
                context.addLine(to: CGPoint(x: end.x - 12 * cos(angle + offset), y: end.y - 12 * sin(angle + offset)))
            }
            context.strokePath()
        }
    }
}
