import AppKit

@MainActor
final class PanelAlignmentGuides {
    private(set) var panel: NSPanel?

    func show(for result: PanelSnapResult, on screen: NSScreen, above popup: NSWindow) {
        guard result.snappedX || result.snappedY else { hide(); return }
        let panel = panel ?? makePanel()
        let view = panel.contentView as! AlignmentGuideView
        let target = PanelPositioning.defaultFrame(size: result.frame.size, in: screen.visibleFrame)
        view.verticalLines = result.snappedX ? [target.minX - screen.visibleFrame.minX, target.maxX - screen.visibleFrame.minX] : []
        view.horizontalLine = result.snappedY ? target.maxY - screen.visibleFrame.minY : nil
        view.guideColor = popup.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .systemTeal : .systemBlue
        panel.setFrame(screen.visibleFrame, display: false)
        panel.level = NSWindow.Level(rawValue: popup.level.rawValue + 1)
        view.needsDisplay = true
        panel.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = AlignmentGuideView()
        self.panel = panel
        return panel
    }
}

private final class AlignmentGuideView: NSView {
    var verticalLines: [CGFloat] = []
    var horizontalLine: CGFloat?
    var guideColor: NSColor = .systemBlue

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .copy
        NSColor.clear.setFill()
        NSBezierPath(rect: dirtyRect).fill()
        NSGraphicsContext.restoreGraphicsState()
        guideColor.withAlphaComponent(0.55).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1
        path.setLineDash([5, 6], count: 2, phase: 0)
        for x in verticalLines {
            path.move(to: NSPoint(x: x, y: bounds.minY))
            path.line(to: NSPoint(x: x, y: bounds.maxY))
        }
        if let y = horizontalLine {
            path.move(to: NSPoint(x: bounds.minX, y: y))
            path.line(to: NSPoint(x: bounds.maxX, y: y))
        }
        path.stroke()
    }
}
