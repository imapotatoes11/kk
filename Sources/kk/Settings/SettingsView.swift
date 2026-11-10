import KeyboardShortcuts
import SwiftUI

enum SettingsSection: String, CaseIterable {
    case general, connection, annotations, shortcuts, advanced, about

    var title: String {
        switch self {
        case .connection: "Connection"
        case .general: "General"
        case .annotations: "Annotations"
        case .shortcuts: "Shortcuts"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .connection: "network"
        case .general: "slider.horizontal.3"
        case .annotations: "pencil.tip.crop.circle"
        case .shortcuts: "keyboard"
        case .advanced: "gearshape.2"
        case .about: "info.circle"
        }
    }
}

@MainActor
final class SettingsSelection: ObservableObject {
    @Published var section: SettingsSection = .general
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var preferences: Preferences
    @ObservedObject var selection: SettingsSelection
    @State private var apiKey = ""
    @State private var hasSavedKey = false
    @State private var statusMessage: String?
    @State private var keyError = false

    var body: some View {
        Group {
            switch selection.section {
            case .connection: connection
            case .general: CustomizationView(preferences: preferences)
            case .annotations: AnnotationsSettingsView(preferences: preferences)
            case .shortcuts: shortcuts
            case .advanced: AdvancedSettingsView(preferences: preferences)
            case .about: about
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(preferences.accent.color)
        .accentColor(preferences.accent.color)
        .onAppear { hasSavedKey = appState.keychain.loadAPIKey()?.isEmpty == false }
    }

    private var connection: some View {
        Form {
            Section {
                TextField("Base URL", text: $preferences.baseURL, prompt: Text("https://api.openai.com/v1"))
                    .autocorrectionDisabled()
                TextField("Model", text: $preferences.model, prompt: Text("Model ID"))
                    .autocorrectionDisabled()
            } header: {
                Text("OpenAI-compatible API")
            } footer: {
                Text("Use a vision-capable model to ask about your screen or attached images. Changes save automatically.")
            }

            Section {
                SecureField("API key", text: $apiKey, prompt: Text(hasSavedKey ? "Saved in Keychain" : "Optional for local endpoints"))
                    .onSubmit(saveKey)
                HStack(spacing: 12) {
                    Label(hasSavedKey ? "Key saved in Keychain" : "No key saved", systemImage: hasSavedKey ? "lock.shield" : "key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear", action: clearKey)
                        .disabled(!hasSavedKey && apiKey.isEmpty)
                    Button("Save key", action: saveKey)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let statusMessage {
                    Label(statusMessage, systemImage: keyError ? "exclamationmark.triangle" : "checkmark.circle")
                        .foregroundStyle(keyError ? Color.red : Color.secondary)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Authentication")
            } footer: {
                Text("Keys are stored only in macOS Keychain. Enter a new key to replace the saved one.")
            }

            Section {
                Label(destinationDescription, systemImage: "arrow.up.right.circle")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                if let configurationError {
                    Label(configurationError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Privacy")
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private var shortcuts: some View {
        Form {
            Section {
                Picker("⌘C in the popup", selection: $preferences.copyShortcutAction) {
                    ForEach(CopyShortcutAction.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Copy answer")
            } footer: {
                Text("Selected text keeps normal copy behavior. Answer copying shows success or failure; the popup closes only after a successful copy.")
            }
            Section {
                KeyboardShortcuts.Recorder("Show or hide kk", name: .askKK)
                HStack {
                    Text("Default: ⌘⌥K")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore default") { KeyboardShortcuts.reset(.askKK) }
                }
            } header: {
                Text("Global shortcut")
            } footer: {
                Text("Click the recorder, then press your preferred key combination. The shortcut works in any app. Use the recorder’s clear button to disable it.")
            }

            Section("In the popup") {
                LabeledContent("Send question", value: "Return")
                LabeledContent("New line", value: "Shift + Return")
                LabeledContent("Attach copied file or image", value: "⌘V")
                LabeledContent("Close popup or screen preview", value: "Escape")
                LabeledContent("Open settings", value: "⌘,")
            }

            Section {
                Text("Drag kk or the header to move the popup. Resize it from an edge or corner. Long answers scroll; scrolling up pauses automatic following.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                // The icon Finder and the Dock show: AppIcon.icon rendered for the
                // current icon style (light, dark, clear, or tinted). The bundle's
                // applicationIconImage is the static light fallback.
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable()
                    .frame(width: 64, height: 64)
                    .id(colorScheme)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("kk").font(.system(size: 26, weight: .semibold))
                        Text(AppVersion().description)
                            .font(.callout).foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Text("Ask about your screen, then keep the conversation going.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Markdown, code, tables, math, and diagrams", systemImage: "textformat")
                    Label("Screenshots and attachments stay in memory", systemImage: "rectangle.on.rectangle")
                    Label("Requests go directly to your API provider", systemImage: "network")
                    Label("No saved conversations or analytics", systemImage: "lock.shield")
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 16) {
                    UpdateSettingsView(updater: appState.updater)
                    LaunchAtLoginView()
                        .font(.callout)
                        .padding(.horizontal, 16)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
            Divider()
            HStack {
                Button("Show onboarding again") { appState.replayOnboarding() }
                Spacer()
                Button("Quit kk") { NSApp.terminate(nil) }
            }
        }
        .padding(24)
    }

    private var destinationDescription: String {
        let configuration = APIConfiguration(baseURL: preferences.baseURL, apiKey: "", model: preferences.model)
        return "Questions, attached screens, and attached files go directly to \(configuration.host ?? "your configured endpoint"). Screenshots and attachments stay in memory. No conversation history or analytics are stored."
    }

    private var configurationError: String? {
        do {
            _ = try APIConfiguration(baseURL: preferences.baseURL, apiKey: "", model: preferences.model).validated()
            return nil
        } catch { return error.localizedDescription }
    }

    private func saveKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try appState.keychain.saveAPIKey(trimmed)
            apiKey = ""
            hasSavedKey = true
            keyError = false
            statusMessage = "Saved in Keychain"
        } catch {
            keyError = true
            statusMessage = error.localizedDescription
        }
    }

    private func clearKey() {
        do {
            try appState.keychain.deleteAPIKey()
            apiKey = ""
            hasSavedKey = false
            keyError = false
            statusMessage = "Key cleared"
        } catch {
            keyError = true
            statusMessage = error.localizedDescription
        }
    }
}
