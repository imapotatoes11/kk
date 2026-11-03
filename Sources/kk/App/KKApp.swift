import AppKit
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

    private var shortcutTask: Task<Void, Never>?
    private var settingsController: SettingsWindowController?
    private(set) var settingsWindow: NSWindow?

    init(preferences: Preferences = Preferences(), keychain: APIKeyStoring = KeychainStore(), clipboard: ClipboardWriting = SystemClipboardWriter(), apiClient: OpenAICompatibleClient = OpenAICompatibleClient()) {
        self.preferences = preferences
        self.keychain = keychain
        captureService = ScreenCaptureService()
        self.apiClient = apiClient
        panelController = PanelController(preferences: preferences)
        copyFeedback = CopyFeedbackController(clipboard: clipboard)
        chat = ChatController(
            preferences: preferences,
            keychain: keychain,
            captureService: captureService,
            apiClient: apiClient
        )
        panelController.onDismiss = { [weak self] in
            self?.dismissPanel()
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

    func togglePanel() {
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
        chat.dismiss()
        panelController.hide()
    }

    func openSettings() {
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

    private func openPanel() {
        guard !panelController.isVisible else { return }

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

        panelController.show(rootView: AnyView(rootView), on: screen)
        panelController.panel?.onCopyShortcut = { [weak self] in self?.handleCopyShortcut() ?? false }
        chat.beginCapture(for: screen)
    }
}
