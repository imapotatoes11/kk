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
    private let preferences: Preferences
    private let clipboard: ClipboardWriting
    private(set) var panel: NSPanel?
    private(set) var lastSucceeded = false
    private var dismissal: Task<Void, Never>?

    init(clipboard: ClipboardWriting = SystemClipboardWriter(), preferences: Preferences = Preferences()) {
        self.preferences = preferences
        self.clipboard = clipboard
    }

    @discardableResult
    func copy(_ text: String, near sourceFrame: NSRect?, successMessage: String = "Answer copied") -> Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let success = hasText && clipboard.write(text)
        lastSucceeded = success
        let message = success ? successMessage : (hasText ? "Couldn’t copy. Try again." : "No answer to copy yet")
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
        panel.appearance = preferences.appearance.nsAppearance
        let host = NSHostingView(rootView: CopyFeedbackView(message: message, success: success, preferences: preferences))
        let size = host.fittingSize
        host.frame.size = size
        panel.contentView = host
        let screen = NSScreen.screens.first { $0.frame.intersects(frame ?? .zero) } ?? NSScreen.main
        let source = frame ?? screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        var target = NSRect(x: source.midX - size.width / 2, y: source.minY - size.height - 6, width: size.width, height: size.height)
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

struct CopyFeedbackView: View {
    let message: String
    let success: Bool
    @ObservedObject var preferences: Preferences

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: success ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(success ? Color.green : Color.secondary)
            Text(message).foregroundStyle(.primary)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background { PopupBackground(material: preferences.popupMaterial, cornerRadius: 1000) }
        .clipShape(Capsule())
        .overlay { Capsule().strokeBorder(success ? Color.green.opacity(0.35) : Color(nsColor: .separatorColor), lineWidth: 0.75) }
        .shadow(color: success ? .green.opacity(0.22) : .clear, radius: 5)
        // The transparent margin keeps the glow inside the noninteractive window.
        .padding(10)
        .fixedSize()
        .materialActiveAppearance(.active)
    }
}
