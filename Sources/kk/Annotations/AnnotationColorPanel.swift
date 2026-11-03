import AppKit
import SwiftUI

@MainActor
final class AnnotationColorPanel {
    private(set) var panel: NSPanel?
    weak var popup: NSWindow?
    private weak var anchor: NSView?
    private var localMonitor: Any?
    private var globalMonitor: Any?
    var isVisible: Bool { panel?.isVisible == true }

    func toggle(from anchor: NSView, preferences: Preferences, onSelection: @escaping () -> Void) {
        if isVisible { close(); return }
        guard let source = anchor.window else { return }
        self.anchor = anchor
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 288, height: 60), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: max(source.level.rawValue, popup?.level.rawValue ?? 0) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.appearance = preferences.appearance.nsAppearance
        let binding = Binding(get: { preferences.annotationColor }, set: { [weak self] color in
            preferences.annotationColor = color
            self?.close()
            onSelection()
        })
        let host = NSHostingView(rootView: AnnotationColorPicker(selection: binding).padding(16).modifier(PopupSurface(material: preferences.popupMaterial)))
        host.sizingOptions = []
        panel.contentView = host
        self.panel = panel
        updatePosition()
        panel.orderFrontRegardless()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.close(); return nil }
            } else if event.window !== self.panel && !self.anchorScreenFrame.contains(NSEvent.mouseLocation) { self.close() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.close() }
    }

    private var anchorScreenFrame: CGRect {
        guard let anchor, let window = anchor.window else { return .zero }
        return window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
    }
    func updatePosition() {
        guard let panel, let screen = anchor?.window?.screen ?? NSScreen.main else { return }
        panel.setFrame(Self.frame(anchor: anchorScreenFrame, visible: screen.visibleFrame, size: panel.frame.size, avoiding: popup?.frame), display: true)
    }
    nonisolated static func frame(anchor: CGRect, visible: CGRect, size: CGSize, avoiding popup: CGRect? = nil) -> CGRect {
        let x = min(max(anchor.midX - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let below = CGRect(x: x, y: anchor.minY - size.height - 8, width: size.width, height: size.height)
        let above = CGRect(x: x, y: anchor.maxY + 8, width: size.width, height: size.height)
        for candidate in [below, above] where visible.contains(candidate) && !(popup?.intersects(candidate) ?? false) { return candidate }
        var fallback = below
        fallback.origin.y = min(max(below.minY, visible.minY + 8), visible.maxY - size.height - 8)
        return fallback
    }
    func close() {
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        panel?.orderOut(nil)
        panel = nil
        anchor = nil
    }
}
