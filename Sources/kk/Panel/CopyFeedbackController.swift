import AppKit
import SwiftUI

@MainActor
protocol ClipboardWriting {
    func write(_ text: String) -> Bool
}

struct SystemClipboardWriter: ClipboardWriting {
    var pasteboard: NSPasteboard = .general
    func write(_ text: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }
}

@MainActor
final class CopyFeedbackController {
    private let clipboard: ClipboardWriting
    private(set) var panel: NSPanel?
    private(set) var lastSucceeded = false
    private var dismissal: Task<Void, Never>?

    init(clipboard: ClipboardWriting = SystemClipboardWriter()) {
        self.clipboard = clipboard
    }

    @discardableResult
    func copy(_ text: String, near sourceFrame: NSRect?) -> Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let success = hasText && clipboard.write(text)
        lastSucceeded = success
        let message = success ? "Answer copied" : (hasText ? "Couldn’t copy. Try again." : "No answer to copy yet")
        show(message: message, success: success, near: sourceFrame)
        return success
    }

    func hide() {
        dismissal?.cancel()
        panel?.orderOut(nil)
    }

    private func show(message: String, success: Bool, near frame: NSRect?) {
        dismissal?.cancel()
        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(rootView:
            Label(message, systemImage: success ? "checkmark.circle.fill" : "exclamationmark.circle")
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 16)
                .frame(width: 280, height: 44)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor)) }
        )
        let screen = NSScreen.screens.first { $0.frame.intersects(frame ?? .zero) } ?? NSScreen.main
        let source = frame ?? screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        var target = NSRect(x: source.midX - 140, y: source.minY - 56, width: 280, height: 44)
        if let screen { target = PanelPositioning.clamped(target, to: screen) }
        panel.setFrame(target, display: true)
        panel.orderFrontRegardless()
        dismissal = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        self.panel = panel
        return panel
    }
}
