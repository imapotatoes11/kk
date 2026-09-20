import AppKit
import SwiftUI

@MainActor
final class PanelController {
    private(set) var panel: KKPanel?
    private var screen: NSScreen?
    var onDismiss: (() -> Void)?

    var isVisible: Bool { panel?.isVisible == true }

    func show(rootView: AnyView, on screen: NSScreen) {
        self.screen = screen

        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(rootView: rootView)
        panel.setFrame(PanelPositioning.initialFrame(on: screen), display: false)
        panel.orderFrontRegardless()
        panel.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func resize(height: CGFloat, animated: Bool = true) {
        guard let panel, let screen else { return }
        let targetHeight = min(height, UIConstants.panelMaxHeight)
        var frame = panel.frame
        let top = frame.maxY
        frame.size.height = targetHeight
        frame.origin.y = top - targetHeight
        let shouldAnimate = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrame(PanelPositioning.clamped(frame, to: screen), display: true, animate: shouldAnimate)
    }

    private func makePanel() -> KKPanel {
        let panel = KKPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.onEscape = { [weak self] in
            self?.onDismiss?()
        }
        self.panel = panel
        return panel
    }
}
