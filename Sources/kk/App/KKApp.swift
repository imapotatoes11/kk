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
    let keychain: APIKeyStoring
    let captureService: ScreenCaptureService
    let apiClient: OpenAICompatibleClient
    let chat: ChatController
    let panelController: PanelController
    let copyFeedback: CopyFeedbackController
    let annotations: AnnotationController
    private var deactivationObserver: AnyCancellable?
    private var previousApplication: NSRunningApplication?
    private var settingsWasKeyWhenOpening = false
    private var settingsCloseObserver: AnyCancellable?

    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private(set) var permissionSetupActive = false
    private var permissionSetupWindows: [NSWindow] = []
    private var permissionRelaunchInProgress = false
    private var onboarding: OnboardingController?
    private var shortcutTask: Task<Void, Never>?
    private var settingsController: SettingsWindowController?
    private(set) var settingsWindow: NSWindow?

    init(preferences: Preferences = Preferences(), keychain: APIKeyStoring = KeychainStore(), clipboard: ClipboardWriting = SystemClipboardWriter(), apiClient: OpenAICompatibleClient = OpenAICompatibleClient(), captureService: ScreenCaptureService = ScreenCaptureService()) {
        self.preferences = preferences
        self.keychain = keychain
        self.captureService = captureService
        self.apiClient = apiClient
        panelController = PanelController(preferences: preferences)
        copyFeedback = CopyFeedbackController(clipboard: clipboard)
        annotations = AnnotationController(preferences: preferences)
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
            self?.panelController.panel?.orderFrontRegardless()
            self?.panelController.panel?.makeKey()
        }
        annotations.onEmptyCanvasClick = { [weak self] in
            guard let self, !self.chat.hasSubmitted, self.chat.prompt.trimmingCharacters(in: .whitespacesAndNewlines).count <= 2 else { return false }
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
        chat.onSubmit = { [weak self] in self?.annotations.end() }
        chat.preparePreview = { [weak self] data in self?.annotations.previewImage(fallback: data) ?? data }
        chat.prepareScreen = { [weak self] data in
            guard let self else { throw CancellationError() }
            return try await self.annotations.prepareImage(fallback: data)
        }

        deactivationObserver = NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard !NSApp.isActive else { return }
                self?.dismissShortDraftAfterDeactivation()
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
            dismissPanel()
        } else {
            openPanel()
        }
    }

    func askFromMenu() {
        togglePanel()
    }

    func dismissPanel() {
        guard annotations.allowDiscard() else { return }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor); self.outsideClickMonitor = nil }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor); self.localClickMonitor = nil }
        let settings = settingsWindow as? KKSettingsWindow
        if !settingsWasKeyWhenOpening { settings?.suppressAutomaticKey = true }
        annotations.end()
        chat.dismiss()
        panelController.hide()
        if NSApp.isActive, let previousApplication, !previousApplication.isTerminated { previousApplication.activate(options: []) }
        previousApplication = nil
        Task { @MainActor [weak settings] in
            try? await Task.sleep(for: .milliseconds(100))
            settings?.suppressAutomaticKey = false
        }
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
                    if !NSApp.windows.contains(where: { $0 is KKSettingsWindow && $0.isVisible }) { NSApp.setActivationPolicy(.accessory) }
                }
                if self.panelController.isVisible { self.annotations.resume() }
            }
        window.level = annotations.isActive ? NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3) : .normal
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func copyAnswer(_ text: String) {
        copyFeedback.copy(text, near: panelController.panel?.frame)
    }

    @discardableResult
    func handleCopyShortcut() -> Bool {
        guard preferences.copyShortcutAction != .disabled else { return false }
        let answer = chat.messages.last(where: { $0.role == .assistant })?.content ?? ""
        let succeeded = copyFeedback.copy(answer, near: panelController.panel?.frame)
        if succeeded && preferences.copyShortcutAction == .copyAndClose { dismissPanel() }
        return true
    }

    func replayOnboarding() {
        guard annotations.allowDiscard() else { return }
        annotations.end()
        chat.dismiss()
        panelController.hide()
        settingsWindow?.close()
        presentOnboarding()
    }

    private func presentOnboarding() {
        onboarding = OnboardingController(appState: self) { [weak self] in self?.openPanel() }
        onboarding?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var shouldDismissShortDraft: Bool {
        !permissionSetupActive && panelController.isVisible && !chat.hasSubmitted &&
        chat.prompt.trimmingCharacters(in: .whitespacesAndNewlines).count <= 2 &&
        annotations.document.visibleAnnotations.isEmpty && !chat.isPreviewPresented
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
        settingsWasKeyWhenOpening = settingsWindow?.isKeyWindow == true
        (settingsWindow as? KKSettingsWindow)?.suppressAutomaticKey = false
        annotations.begin(on: screen)
        panelController.show(rootView: AnyView(rootView), on: screen)
        panelController.panel?.onCopyShortcut = { [weak self] in self?.handleCopyShortcut() ?? false }
        annotations.textPanel = panelController.panel
        chat.beginCapture(for: screen)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in self?.dismissEmptyPopupOnOutsideClick() }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissEmptyPopupOnOutsideClick()
            return event
        }
    }
}
