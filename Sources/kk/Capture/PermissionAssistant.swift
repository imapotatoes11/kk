import AppKit
import CoreGraphics
import SwiftUI

/// A file drag source, not a permission grant: System Settings still owns consent.
@MainActor
final class PermissionAssistant {
    static let shared = PermissionAssistant()
    private(set) var panel: NSPanel?
    private let guidance = PermissionGuidance()
    private let dragArrow = PermissionDragArrow()
    var onWillOpen: (() -> Void)?
    var onDidClose: (() -> Void)?
    var onRelaunch: (() async -> Bool)?
    private let accessCheck: () -> Bool
    private let canAutomaticallyReopen: () -> Bool
    init(accessCheck: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
         canAutomaticallyReopen: @escaping () -> Bool = {
             NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Bundle.main.bundleIdentifier
         }) {
        self.accessCheck = accessCheck
        self.canAutomaticallyReopen = canAutomaticallyReopen
    }
    var automaticallyReopen: Bool {
        get { guidance.automaticallyReopen }
        set { guidance.automaticallyReopen = newValue }
    }
    private var followTask: Task<Void, Never>?

    func open(appURL: URL = Bundle.main.bundleURL) {
        onWillOpen?()
        let prepared = PreparedDragApp.prepare(appURL: appURL)
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
        show(appURL: appURL, prepared: prepared)
    }

    func show(appURL: URL, prepared: PreparedDragApp? = nil) {
        close(notify: false)
        let prepared = prepared ?? PreparedDragApp.prepare(appURL: appURL)
        guidance.preparationError = prepared.error
        guidance.appDropped = false
        guidance.showManualRecovery = false
        guidance.accessEnabled = false
        guidance.message = "Then turn on screen recording."
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 160), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: PermissionAssistantView(prepared: prepared, onDropAccepted: { [weak self] in self?.appWasDropped() }, guidance: guidance, onClose: { [weak self] in self?.close() }, onReopen: { [weak self] in
            Task { await self?.reopen() }
        }))
        self.panel = panel
        position()
        panel.orderFrontRegardless()
        followTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.accessCheck() {
                    self.guidance.accessEnabled = true
                    self.dragArrow.hide()
                    if self.guidance.automaticallyReopen {
                        guard self.canAutomaticallyReopen() else {
                            self.guidance.message = "Access enabled. Choose Quit & Reopen if asked."
                            self.position()
                            try? await Task.sleep(for: .milliseconds(400))
                            continue
                        }
                        self.guidance.message = "Access enabled. Reopening kk…"
                        try? await Task.sleep(for: .milliseconds(800))
                        guard !Task.isCancelled else { return }
                        guard self.canAutomaticallyReopen() else { continue }
                        await self.reopen()
                    } else { self.guidance.message = "Access enabled. Reopen kk when ready." }
                    return
                }
                self.position()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    var hasAcceptedDrop: Bool { guidance.appDropped }

    func appWasDropped() {
        guidance.appDropped = true
        guidance.message = "Enable kk. If macOS asks, choose Quit & Reopen."
        dragArrow.hide()
    }

    private func reopen() async {
        guard !guidance.isReopening else { return }
        guidance.isReopening = true
        let succeeded = await onRelaunch?() ?? false
        guidance.isReopening = false
        if succeeded { close() }
        else { guidance.message = "Close this helper to finish your work, then reopen kk." }
    }

    func close(notify: Bool = true) {
        let wasOpen = panel != nil
        dragArrow.hide()
        followTask?.cancel()
        followTask = nil
        panel?.orderOut(nil)
        panel = nil
        if wasOpen && notify { onDidClose?() }
    }

    nonisolated static func helperFrame(beside settings: CGRect?, visible: CGRect, size: CGSize) -> CGRect {
        var frame = CGRect(x: (settings?.midX ?? visible.midX) - size.width / 2,
                           y: (settings?.minY ?? visible.midY) - size.height - 12, width: size.width, height: size.height)
        if frame.minY < visible.minY + 12, let settings {
            frame.origin.y = settings.midY - size.height / 2
            frame.origin.x = settings.maxX + 12
        }
        frame.origin.x = min(max(frame.minX, visible.minX + 12), visible.maxX - size.width - 12)
        frame.origin.y = min(max(frame.minY, visible.minY + 12), visible.maxY - size.height - 12)
        return frame
    }

    private func position() {
        guard let panel else { return }
        let settingsPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first?.processIdentifier
        var settingsFrame: CGRect?
        // Window geometry requires neither Accessibility access nor a screen image.
        if let settingsPID, let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
           let primary = NSScreen.screens.first {
            for info in windows where (info[kCGWindowOwnerPID as String] as? Int32) == settingsPID && (info[kCGWindowLayer as String] as? Int) == 0 {
                if let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                   let rect = CGRect(dictionaryRepresentation: bounds), rect.width > 300, rect.height > 200 {
                    settingsFrame = CGRect(x: rect.minX, y: primary.frame.maxY - rect.maxY, width: rect.width, height: rect.height)
                    break
                }
            }
        }
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: settingsFrame?.midX ?? NSEvent.mouseLocation.x, y: settingsFrame?.midY ?? NSEvent.mouseLocation.y)) } ?? NSScreen.main
        guard let screen else { return }
        panel.setFrame(Self.helperFrame(beside: settingsFrame, visible: screen.visibleFrame, size: panel.frame.size), display: true)
        if let settingsFrame, !guidance.accessEnabled, !guidance.appDropped, guidance.preparationError == nil {
            let source = CGPoint(x: panel.frame.minX + 44, y: panel.frame.midY + 28)
            let target = CGPoint(x: min(max(source.x, settingsFrame.minX + 32), settingsFrame.maxX - 32), y: settingsFrame.minY + 28)
            dragArrow.show(from: source, to: target)
        } else { dragArrow.hide() }
    }
}

@MainActor
final class PermissionGuidance: ObservableObject {
    @Published var appDropped = false
    @Published var preparationError: String?
    @Published var showManualRecovery = false
    @Published var automaticallyReopen = true
    @Published var accessEnabled = false
    @Published var isReopening = false
    @Published var message = "Then turn on screen recording."
}

private struct PermissionAssistantView: View {
    let prepared: PreparedDragApp
    let onDropAccepted: () -> Void
    @ObservedObject var guidance: PermissionGuidance
    let onClose: () -> Void
    let onReopen: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            DraggableAppIcon(prepared: prepared, onDropAccepted: onDropAccepted).frame(width: 56, height: 64)
            VStack(alignment: .leading, spacing: 6) {
                Text(guidance.appDropped ? "Finish in System Settings" : "Drag kk into the app list").font(.system(size: 14, weight: .semibold))
                Text(guidance.preparationError ?? guidance.message).font(.system(size: 12)).foregroundStyle(.secondary)
                Text("If asked, choose Quit & Reopen in Settings.").font(.system(size: 11)).foregroundStyle(.secondary)
                Toggle("Reopen when I return to kk", isOn: $guidance.automaticallyReopen).font(.system(size: 11))
                DisclosureGroup("Already enabled?", isExpanded: $guidance.showManualRecovery) {
                    Button("Reopen kk", action: onReopen).font(.system(size: 11)).disabled(guidance.isReopening)
                }.font(.system(size: 11))
            }
            Spacer(minLength: 0)
            Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 11)) }.buttonStyle(.plain).accessibilityLabel("Close permission helper")
        }
        .padding(16)
        .background { PopupBackground(material: .liquidGlass) }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.gray.opacity(0.3), lineWidth: 1) }
    }
}

struct DraggableAppIcon: NSViewRepresentable {
    let prepared: PreparedDragApp
    let onDropAccepted: () -> Void
    func makeNSView(context: Context) -> AppDragView { AppDragView(appURL: prepared.appURL, prepared: prepared) }
    func updateNSView(_ view: AppDragView, context: Context) { view.onDropAccepted = onDropAccepted }
}

final class AppDragView: NSView, NSDraggingSource {
    let appURL: URL
    let prepared: PreparedDragApp
    var onDropAccepted: (() -> Void)?
    init(appURL: URL, prepared: PreparedDragApp? = nil) {
        self.appURL = appURL
        self.prepared = prepared ?? PreparedDragApp.prepare(appURL: appURL)
        super.init(frame: .zero)
        setAccessibilityLabel("Drag kk into System Settings")
    }
    required init?(coder: NSCoder) { nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        prepared.icon.draw(in: bounds.insetBy(dx: 2, dy: 6))
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) {
        // Retain this view as the mouse target until the user starts dragging.
    }
    override func mouseDragged(with event: NSEvent) {
        guard prepared.isReady else { return }
        let item = NSDraggingItem(pasteboardWriter: appURL as NSURL)
        item.setDraggingFrame(bounds, contents: prepared.icon)
        beginDraggingSession(with: [item], event: event, source: self)
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        finishDrag(operation: operation)
    }
    func finishDrag(operation: NSDragOperation) {
        if operation.contains(.copy) { onDropAccepted?() }
    }
}
