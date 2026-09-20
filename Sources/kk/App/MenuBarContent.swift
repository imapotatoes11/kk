import SwiftUI
import AppKit

struct MenuBarContent: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button("Ask kk") {
            appState.askFromMenu()
        }
        .keyboardShortcut("k", modifiers: [.command, .option])

        Divider()

        Button("Settings…") {
            appState.openSettings()
        }

        Divider()

        Button("Quit kk") {
            appState.dismissPanel()
            NSApplication.shared.terminate(nil)
        }
    }
}
