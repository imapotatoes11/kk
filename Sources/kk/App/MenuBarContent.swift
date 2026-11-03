import SwiftUI
import AppKit
import KeyboardShortcuts

struct MenuBarContent: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button("Ask kk") {
            appState.askFromMenu()
        }
        .globalKeyboardShortcut(.askKK)

        Divider()

        Button("Settings…") {
            appState.openSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit kk") {
            appState.dismissPanel()
            NSApplication.shared.terminate(nil)
        }
    }
}
