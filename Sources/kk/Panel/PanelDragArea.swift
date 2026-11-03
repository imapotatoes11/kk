import AppKit
import SwiftUI

struct PanelDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let panel = window as? KKPanel, panel.onDragFrame != nil else {
                window?.performDrag(with: event)
                return
            }
            panel.onBeginDrag?()
            defer { panel.onEndDrag?() }
            let startMouse = NSEvent.mouseLocation
            let startFrame = panel.frame
            var moved = false
            while panel.isVisible {
                guard let next = panel.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: Date(timeIntervalSinceNow: 0.1), inMode: .eventTracking, dequeue: true) else {
                    if NSEvent.pressedMouseButtons & 1 == 0 { break }
                    continue
                }
                if next.type == .leftMouseDragged { moved = true }
                if moved {
                    let mouse = NSEvent.mouseLocation
                    let frame = NSRect(x: startFrame.minX + mouse.x - startMouse.x, y: startFrame.minY + mouse.y - startMouse.y, width: startFrame.width, height: startFrame.height)
                    panel.onDragFrame?(frame, mouse)
                }
                if next.type == .leftMouseUp { break }
            }
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}
