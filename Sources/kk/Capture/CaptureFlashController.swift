import AppKit

enum CaptureFlash: String, CaseIterable, Identifiable {
    case off, low, full
    var id: String { rawValue }
    var title: String {
        switch self { case .off: "Off"; case .low: "Low"; case .full: "Full" }
    }
    var opacity: CGFloat {
        switch self { case .off: 0; case .low: 0.25; case .full: 1 }
    }
}

/// Feedback is displayed after the pixels have been captured. It never takes focus
/// and, like kk's other windows, is excluded from subsequent desktop captures.
@MainActor
final class CaptureFlashController {
    private(set) var panels: [CGDirectDisplayID: NSPanel] = [:]
    private var dismissals: [CGDirectDisplayID: Task<Void, Never>] = [:]
    private var tokens: [CGDirectDisplayID: UUID] = [:]

    func flash(displayID: CGDirectDisplayID?, mode: CaptureFlash) {
        guard mode != .off, let displayID,
              let screen = NSScreen.screens.first(where: { DisplayResolver.displayID(for: $0) == displayID }) else { return }
        dismissals.removeValue(forKey: displayID)?.cancel()
        panels.removeValue(forKey: displayID)?.orderOut(nil)
        let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .white
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.sharingType = .none
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = reduceMotion ? min(mode.opacity, 0.15) : mode.opacity
        panel.orderFrontRegardless()
        panels[displayID] = panel
        let token = UUID()
        tokens[displayID] = token
        dismissals[displayID] = Task { [weak self, panel] in
            defer { panel.orderOut(nil) }
            // One short flash, never a repeating animation. Reduce Motion also lowers
            // intensity instead of producing an abrupt full-white transition.
            try? await Task.sleep(for: .milliseconds(30))
            guard !Task.isCancelled, let self, self.tokens[displayID] == token else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = reduceMotion ? 0.08 : 0.16
                panel.animator().alphaValue = 0
            }
            guard !Task.isCancelled, self.tokens[displayID] == token else { return }
            panel.orderOut(nil)
            self.panels[displayID] = nil
            self.dismissals[displayID] = nil
            self.tokens[displayID] = nil
        }
    }

    func cancel() {
        dismissals.values.forEach { $0.cancel() }
        dismissals.removeAll()
        panels.values.forEach { $0.orderOut(nil) }
        panels.removeAll()
        tokens.removeAll()
    }
}
