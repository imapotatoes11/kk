import AppKit
import Combine
import KeyboardShortcuts
import SwiftUI

@main
struct KKApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(appState)
        } label: {
            Image(systemName: "text.bubble")
                .accessibilityLabel("kk")
        }

    }
}

@MainActor
final class AppState: ObservableObject {
    let preferences: Preferences
    let updater = AppUpdater()
    let keychain: APIKeyStoring
    let captureService: ScreenCaptureService
    let captureFlash = CaptureFlashController()
    let apiClient: OpenAICompatibleClient
    let chat: ChatController
    let panelController: PanelController
    let copyFeedback: CopyFeedbackController
    let annotations: AnnotationController
    private var deactivationObserver: AnyCancellable?
    private var iconSubscription: AnyCancellable?
    private var captureScreens: [NSScreen] = []
    private var previousApplication: NSRunningApplication?
    var confirmChatDismissal: (() -> Bool)?
    private var dismissing = false
    private var settingsWasKeyWhenOpening = false
    private var settingsCloseObserver: AnyCancellable?

    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private(set) var permissionSetupActive = false
    private var permissionSetupWindows: [NSWindow] = []
    private var permissionRelaunchInProgress = false
    private var onboarding: OnboardingController?
    var onboardingWindow: NSWindow? { onboarding?.window }
    private var shortcutTask: Task<Void, Never>?
    private var settingsController: SettingsWindowController?
    private(set) var settingsWindow: NSWindow?
    private var attachmentPicker: NSOpenPanel?
    var attachmentPickerActive: Bool { attachmentPicker != nil }
    private var pendingOutsideDismissal: Task<Void, Never>?
    private lazy var attachmentDropHandler: AttachmentDropHandler = {
        let handler = AttachmentDropHandler()
        handler.isEnabled = { [weak self] in
            guard let self else { return false }
            return !self.chat.composerDisabled && !self.permissionSetupActive
        }
        handler.onTargetChange = { [weak self] targeted in
            guard let self, self.chat.isDropTargeted != targeted else { return }
            self.chat.isDropTargeted = targeted
        }
        handler.onDrop = { [weak self] pasteboard in
            guard let self, self.chat.addAttachments(from: pasteboard) else { return false }
            // Dropping from another app leaves it active; bring the question field back.
            NSApp.activate(ignoringOtherApps: true)
            self.panelController.panel?.focusPrompt()
            return true
        }
        return handler
    }()

    init(preferences: Preferences = Preferences(), keychain: APIKeyStoring = KeychainStore(), clipboard: ClipboardWriting = SystemClipboardWriter(), apiClient: OpenAICompatibleClient = OpenAICompatibleClient(), captureService: ScreenCaptureService = ScreenCaptureService()) {
        self.preferences = preferences
        self.keychain = keychain
        var configuredCapture = captureService
        let flash = self.captureFlash
        let existingFeedback = configuredCapture.onCaptureCompleted
        configuredCapture.onCaptureCompleted = { [weak preferences, weak flash] displayID in
            existingFeedback?(displayID)
            guard let preferences, let flash else { return }
            flash.flash(displayID: displayID, mode: preferences.captureFlash)
        }
        let captureService = configuredCapture
        self.captureService = captureService
        self.apiClient = apiClient
        panelController = PanelController(preferences: preferences, placementCapture: { try await captureService.capturePlacementImage(displayID: $0) })
        copyFeedback = CopyFeedbackController(clipboard: clipboard, preferences: preferences)
        annotations = AnnotationController(preferences: preferences, captureService: captureService)
        chat = ChatController(
            preferences: preferences,
            keychain: keychain,
            captureService: captureService,
            apiClient: apiClient
        )
        panelController.onDismiss = { [weak self] in
            self?.dismissPanel()
        }

        annotations.onActiveChange = { [weak self] active in self?.panelController.annotationLayerActive = active }
        annotations.onFocusPopup = { [weak self] in
            self?.panelController.panel?.focusPrompt()
        }
        annotations.onEmptyCanvasClick = { [weak self] in
            guard let self, !self.chat.hasSubmitted, self.chat.pendingAttachments.isEmpty,
                  self.chat.prompt.trimmingCharacters(in: .whitespacesAndNewlines).count <= 2 else { return false }
            self.dismissPanel()
            return true
        }
        annotations.onDismiss = { [weak self] in self?.dismissPanel() }
        chat.onCaptureReady = { [weak self] snapshot in self?.annotations.receiveCapture(snapshot) }
        chat.onRemoveScreen = { [weak self] in
            guard let self else { return true }
            guard self.annotations.allowDiscard() else { return false }
            self.annotations.end()
            return true
        }
        chat.onSubmit = { [weak self] in
            self?.annotations.end()
            self?.panelController.moveToBlankSpace()
        }
        chat.onPrepareFollowUp = { [weak self] in
            // Runs when an answer finishes or is stopped. The user may have moved on to another app.
            guard let self else { return }
            self.prepareFollowUp(focusPopup: self.preferences.focusOnAnswerComplete)
        }
        chat.onPickFiles = { [weak self] in self?.presentAttachmentPicker() }
        chat.onAnnotate = { [weak self] in
            guard let self else { return }
            if self.annotations.canvasPanel != nil { self.annotations.focusDrawing() }
            else { self.prepareFollowUp() }
        }
        chat.preparePreview = { [weak self] data in self?.annotations.previewImage(fallback: data) ?? data }
        chat.prepareScreen = { [weak self] data in
            guard let self else { throw CancellationError() }
            if self.annotations.isActive { return try await self.annotations.prepareImage(fallback: data) }
            // With annotation mode disabled, refresh at send time as well.
            guard let screen = self.captureScreens.first else { return data }
            return try await self.captureService.captureSnapshot(displayID: DisplayResolver.displayID(for: screen)).data
        }

        chat.prepareAdditionalScreens = { [weak self] in
            guard let self else { throw CancellationError() }
            if self.annotations.isActive && self.annotations.document.isFrozen { return self.chat.additionalScreenData }
            var images: [Data] = []
            for screen in self.captureScreens.dropFirst() {
                try Task.checkCancellation()
                images.append(try await self.captureService.captureSnapshot(displayID: DisplayResolver.displayID(for: screen)).data)
            }
            return images
        }

        iconSubscription = preferences.$iconStyle.removeDuplicates().sink { style in
            if let image = style.image { NSApplication.shared.applicationIconImage = image }
        }
        deactivationObserver = NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard !NSApp.isActive else { return }
                self?.dismissUnlessDragStarts { $0.dismissShortDraftAfterDeactivation() }
            }
        PermissionAssistant.shared.onWillOpen = { [weak self] in self?.beginPermissionSetup() }
        PermissionAssistant.shared.onDidClose = { [weak self] in self?.endPermissionSetup() }
        PermissionAssistant.shared.onRelaunch = { [weak self] in await self?.relaunchForPermission() ?? false }
        if ProcessInfo.processInfo.arguments.contains("--kk-permission-relaunch") || (preferences.permissionSetupPending && captureService.hasPassiveAccess) {
            preferences.permissionSetupPending = false
            preferences.onboardingComplete = true
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.openPanel()
            }
        }
        shortcutTask = Task { [weak self] in
            for await event in KeyboardShortcuts.events(for: .askKK) where event == .keyUp {
                self?.togglePanel()
            }
        }
    }

    deinit {
        shortcutTask?.cancel()
    }

    func beginPermissionSetup() {
        guard !permissionSetupActive else { return }
        permissionSetupActive = true
        preferences.permissionSetupPending = true
        permissionSetupWindows = [panelController.panel, settingsWindow, onboarding?.window].compactMap { $0 }.filter(\.isVisible)
        chat.suspendCaptureForPermissionSetup()
        annotations.suspend()
        panelController.hide()
        for window in permissionSetupWindows { window.orderOut(nil) }
    }

    func endPermissionSetup() {
        guard permissionSetupActive, !permissionRelaunchInProgress else { return }
        permissionSetupActive = false
        chat.screenCaptureSuspended = false
        for window in permissionSetupWindows { window.orderFrontRegardless() }
        permissionSetupWindows.last?.makeKey()
        permissionSetupWindows = []
        annotations.resume()
        chat.resumeCaptureIfPermitted()
        if captureService.hasPassiveAccess { preferences.permissionSetupPending = false }
    }

    func relaunchForPermission() async -> Bool {
        guard !chat.hasSubmitted, !chat.isPreparingScreen,
              chat.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              annotations.document.visibleAnnotations.isEmpty,
              settingsWindow?.isVisible != true,
              !permissionSetupWindows.contains(where: { $0 === settingsWindow }),
              Bundle.main.bundleURL.pathExtension == "app" else { return false }
        permissionRelaunchInProgress = true
        let wasVisible = panelController.isVisible
        panelController.hide()
        annotations.suspend()
        KeyboardShortcuts.disable(.askKK)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = ["--kk-permission-relaunch"]
        do {
            _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
            NSApp.terminate(nil)
            return true
        } catch {
            permissionRelaunchInProgress = false
            KeyboardShortcuts.enable(.askKK)
            if wasVisible { panelController.panel?.orderFrontRegardless(); panelController.panel?.makeKey() }
            annotations.resume()
            return false
        }
    }

    func togglePanel() {
        if permissionSetupActive {
            NSApp.activate(ignoringOtherApps: true)
            PermissionAssistant.shared.panel?.orderFrontRegardless()
            return
        }
        if panelController.isVisible {
            if chat.hasSubmitted {
                NSApp.activate(ignoringOtherApps: true)
                panelController.panel?.focusPrompt()
            } else {
                dismissPanel()
            }
        } else {
            openPanel()
        }
    }

    func askFromMenu() {
        togglePanel()
    }

    func dismissPanel() {
        guard !dismissing else { return }
        if let picker = attachmentPicker {
            attachmentPicker = nil
            picker.cancel(nil)
        }
        pendingOutsideDismissal?.cancel()
        pendingOutsideDismissal = nil
        dismissing = true
        defer { dismissing = false }
        guard annotations.allowDiscard() else { return }
        if chat.isMultiTurn && preferences.confirmDismissChat {
            let accepted: Bool
            if let confirmChatDismissal { accepted = confirmChatDismissal() }
            else {
                annotations.suspend()
                let alert = NSAlert()
                alert.window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 4)
                alert.messageText = "Close this chat?"
                alert.informativeText = preferences.copyChatOnDismiss ? "The conversation will be copied to your clipboard before closing." : "This conversation will be cleared."
                alert.addButton(withTitle: "Keep chatting")
                alert.addButton(withTitle: "Close chat")
                accepted = alert.runModal() == .alertSecondButtonReturn
                if !accepted { annotations.resume() }
            }
            guard accepted else { return }
        }
        if chat.isMultiTurn && preferences.copyChatOnDismiss {
            guard copyFeedback.copy(chat.clipboardTranscript, near: panelController.panel?.frame, successMessage: "Chat copied") else {
                annotations.resume()
                return
            }
        }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor); self.outsideClickMonitor = nil }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor); self.localClickMonitor = nil }
        let settings = settingsWindow as? KKSettingsWindow
        if !settingsWasKeyWhenOpening { settings?.suppressAutomaticKey = true }
        annotations.end()
        chat.dismiss()
        captureScreens = []
        panelController.hide()
        if NSApp.isActive, let previousApplication, !previousApplication.isTerminated { previousApplication.activate(options: []) }
        previousApplication = nil
        Task { @MainActor [weak settings] in
            try? await Task.sleep(for: .milliseconds(100))
            settings?.suppressAutomaticKey = false
        }
    }

    private func prepareFollowUp(focusPopup: Bool = true) {
        guard panelController.isVisible, !permissionSetupActive else { return }
        captureScreens = DisplayResolver.captureScreens(mode: preferences.captureDisplayMode)
        guard let screen = captureScreens.first else { return }
        annotations.begin(on: screen)
        annotations.focusesPopupOnCapture = focusPopup
        if settingsWindow?.isKeyWindow == true { annotations.suspend() }
        chat.beginCapture(for: screen, additionalScreens: Array(captureScreens.dropFirst()))
    }

    func openSettings() {
        if permissionSetupActive {
            NSApp.activate(ignoringOtherApps: true)
            PermissionAssistant.shared.panel?.orderFrontRegardless()
            return
        }
        annotations.suspend()
        NSApp.setActivationPolicy(.regular)
        let window: NSWindow
        if let existing = settingsWindow {
            window = existing
        } else {
            let controller = SettingsWindowController(appState: self)
            settingsController = controller
            let created = controller.window!
            settingsWindow = created
            window = created
        }
        settingsCloseObserver = NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: window)
            .sink { [weak self] _ in
                guard let self else { return }
                self.settingsWindow?.level = .normal
                Task { @MainActor in
                    await Task.yield()
                    Self.refreshActivationPolicy()
                }
                if self.panelController.isVisible { self.annotations.resume() }
            }
        window.level = .normal
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func copyAnswer(_ text: String) {
        guard !chat.isRevising else { return }
        copyFeedback.copy(text, near: panelController.panel?.frame)
    }

    @discardableResult
    func handleCopyShortcut() -> Bool {
        guard !chat.isRevising, preferences.copyShortcutAction != .disabled else { return false }
        let answer = chat.messages.last(where: { $0.role == .assistant })?.content ?? ""
        let succeeded = copyFeedback.copy(answer, near: panelController.panel?.frame)
        if succeeded && preferences.copyShortcutAction == .copyAndClose { dismissPanel() }
        return true
    }

    func replayOnboarding() {
        guard annotations.allowDiscard() else { return }
        annotations.end()
        chat.dismiss()
        captureScreens = []
        panelController.hide()
        settingsWindow?.close()
        presentOnboarding()
    }

    static func refreshActivationPolicy() {
        let hasWindow = NSApp.windows.contains { ($0 is KKSettingsWindow || $0 is OnboardingWindow) && $0.isVisible }
        NSApp.setActivationPolicy(hasWindow ? .regular : .accessory)
    }

    private func presentOnboarding() {
        if onboarding?.window?.isVisible == true { onboarding?.showWindow(nil); return }
        onboarding = OnboardingController(appState: self) { [weak self] in self?.openPanel() }
        onboarding?.showWindow(nil)
    }

    var dismissShortDraftWouldClose: Bool { shouldDismissShortDraft }

    private var shouldDismissShortDraft: Bool {
        !permissionSetupActive && panelController.isVisible && !chat.hasSubmitted &&
        chat.prompt.trimmingCharacters(in: .whitespacesAndNewlines).count <= 2 &&
        chat.pendingAttachments.isEmpty && !chat.isDropTargeted && !attachmentPickerActive &&
        annotations.document.visibleAnnotations.isEmpty && !chat.isPreviewPresented && !annotations.colorPicker.isVisible
    }

    /// Dragging a file from another app starts with a click outside kk, which would close an
    /// empty popup. Wait until the mouse button is released, and keep kk open if a drag started
    /// so the file can be dropped on it.
    private func dismissUnlessDragStarts(_ dismiss: @escaping @MainActor (AppState) -> Void) {
        pendingOutsideDismissal?.cancel()
        pendingOutsideDismissal = nil
        guard shouldDismissShortDraft else { return }
        guard NSEvent.pressedMouseButtons & 1 != 0 else { dismiss(self); return }
        let dragCount = NSPasteboard(name: .drag).changeCount
        pendingOutsideDismissal = Task { @MainActor [weak self] in
            while NSEvent.pressedMouseButtons & 1 != 0 {
                try? await Task.sleep(for: .milliseconds(50))
                if Task.isCancelled { return }
            }
            guard let self, !Task.isCancelled else { return }
            self.pendingOutsideDismissal = nil
            guard NSPasteboard(name: .drag).changeCount == dragCount else { return }
            dismiss(self)
        }
    }

    func presentAttachmentPicker() {
        guard attachmentPicker == nil, let panel = panelController.panel, panel.isVisible else { return }
        let picker = NSOpenPanel()
        picker.title = "Attach Files"
        picker.prompt = "Attach"
        picker.message = "Choose images, PDFs, or text files to send with your question."
        picker.allowsMultipleSelection = true
        picker.canChooseDirectories = false
        picker.canChooseFiles = true
        picker.resolvesAliases = true
        // Stay above the popup and the annotation canvas.
        picker.level = NSWindow.Level(rawValue: max(panel.level.rawValue, NSWindow.Level.floating.rawValue + 2) + 1)
        attachmentPicker = picker
        NSApp.activate(ignoringOtherApps: true)
        picker.begin { [weak self] response in
            MainActor.assumeIsolated {
                guard let self, self.attachmentPicker === picker else { return }
                self.attachmentPicker = nil
                if response == .OK { self.chat.addAttachments(picker.urls.map { .file($0) }) }
                if self.panelController.isVisible { self.panelController.panel?.focusPrompt() }
            }
        }
    }

    func dismissShortDraftAfterDeactivation() {
        guard shouldDismissShortDraft else { return }
        previousApplication = nil
        dismissPanel()
    }

    func dismissEmptyPopupOnOutsideClick(at location: NSPoint? = nil) {
        guard shouldDismissShortDraft else { return }
        let point = location ?? NSEvent.mouseLocation
        if panelController.panel?.frame.contains(point) == true || annotations.toolbarPanel?.frame.contains(point) == true { return }
        // A click on the active drawing surface starts a mark rather than dismissing it.
        if annotations.document.isDrawing && annotations.canvasPanel?.isVisible == true { return }
        previousApplication = nil // The user's outside click owns the new focus.
        dismissPanel()
    }

    private func openPanel() {
        guard !permissionSetupActive else { return }
        guard !panelController.isVisible else { return }
        if onboarding?.window?.isVisible == true { onboarding?.showWindow(nil); return }

        if !preferences.onboardingComplete {
            presentOnboarding()
            return
        }
        chat.reset()
        guard let screen = DisplayResolver.screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let rootView = PanelRootView(
            chat: chat,
            preferences: preferences,
            panelController: panelController,
            onOpenSettings: openSettings,
            onDismiss: dismissPanel,
            onCopyAnswer: copyAnswer
        )

        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApplication = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        // Blank-space placement keeps chat beside the window the user is working in.
        panelController.avoidedWindowFrame = DisplayResolver.activeWindowFrame()
        settingsWasKeyWhenOpening = settingsWindow?.isKeyWindow == true
        (settingsWindow as? KKSettingsWindow)?.suppressAutomaticKey = false
        // Resolve the focused external window before kk becomes active.
        captureScreens = DisplayResolver.captureScreens(mode: preferences.captureDisplayMode)
        let captureScreen = captureScreens.first ?? screen
        annotations.begin(on: captureScreen)
        panelController.show(rootView: AnyView(rootView), on: screen)
        panelController.panel?.onCopyShortcut = { [weak self] in self?.handleCopyShortcut() ?? false }
        panelController.panel?.attachmentDropHandler = attachmentDropHandler
        annotations.textPanel = panelController.panel
        chat.beginCapture(for: captureScreen, additionalScreens: Array(captureScreens.dropFirst()))
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            let location = NSEvent.mouseLocation
            self?.dismissUnlessDragStarts { $0.dismissEmptyPopupOnOutsideClick(at: location) }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissEmptyPopupOnOutsideClick()
            return event
        }
    }
}
