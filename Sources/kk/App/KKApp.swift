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

    private var shortcutTask: Task<Void, Never>?
    private(set) var settingsWindow: NSWindow?

    init() {
        preferences = Preferences()
        keychain = KeychainStore()
        captureService = ScreenCaptureService()
        apiClient = OpenAICompatibleClient()
        panelController = PanelController()
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
            let shortcut = KeyboardShortcuts.Shortcut(.k, modifiers: [.command, .option])
            for await event in KeyboardShortcuts.events(for: shortcut) where event == .keyUp {
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
            let settings = SettingsView(preferences: preferences).environmentObject(self)
            let created = NSWindow(contentViewController: NSHostingController(rootView: settings))
            created.title = "kk Settings"
            created.styleMask = [.titled, .closable, .miniaturizable]
            created.isReleasedWhenClosed = false
            created.setContentSize(NSSize(width: 500, height: 400))
            created.center()
            settingsWindow = created
            window = created
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
            onDismiss: dismissPanel
        )

        panelController.show(rootView: AnyView(rootView), on: screen)
        chat.beginCapture(for: screen)
    }
}
