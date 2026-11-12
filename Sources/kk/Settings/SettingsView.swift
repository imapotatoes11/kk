import KeyboardShortcuts
import SwiftUI

enum SettingsSection: String, CaseIterable {
    case general, inference, annotations, shortcuts, advanced, about

    var title: String {
        switch self {
        case .inference: "Inference"
        case .general: "General"
        case .annotations: "Annotations"
        case .shortcuts: "Shortcuts"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .inference: "cpu"
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
    @ObservedObject var preferences: Preferences
    @ObservedObject var selection: SettingsSelection
    @State private var apiKey = ""
    @State private var hasSavedKey = false
    @State private var statusMessage: String?
    @State private var keyError = false

    var body: some View {
        Group {
            switch selection.section {
            case .inference: inference
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

    private var inference: some View {
        Form {
            Section {
                TextField("Base URL", text: $preferences.baseURL, prompt: Text("https://api.openai.com/v1"))
                    .autocorrectionDisabled()
                TextField("Model", text: $preferences.model, prompt: Text("Model ID"))
                    .autocorrectionDisabled()
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
                Text("Inference")
            } footer: {
                Text("Any OpenAI-compatible endpoint. Use a vision-capable model to ask about your screen or attached images. The URL and model save automatically; keys are stored only in macOS Keychain.")
            }

            Section {
                Picker("Reasoning effort", selection: $preferences.reasoningEffort) {
                    Text("Off (provider default)").tag("")
                    ForEach(InferenceParameters.efforts, id: \.self) { effort in
                        Text(effort.capitalized).tag(effort)
                    }
                }
                if preferences.reasoningDisabled {
                    HStack {
                        Label("Disabled after this endpoint returned an error", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Try again") { preferences.retryReasoning() }
                    }
                }
            } header: {
                Text("Reasoning")
            } footer: {
                Text("Optionally sends reasoning_effort. Off lets the provider decide. On the first request for each endpoint, model, and effort, an error response disables this parameter and retries once without it.")
            }

            Section {
                TextEditor(text: $preferences.customInstructions)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 72, maxHeight: 140)
                    .overlay(alignment: .topLeading) {
                        if preferences.customInstructions.isEmpty {
                            Text("For example: Answer in British English. Keep answers under five sentences.")
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .accessibilityLabel("Custom instructions")
                    .onChange(of: preferences.customInstructions) { _, text in
                        if text.count > KKCopy.customInstructionsLimit {
                            preferences.customInstructions = String(text.prefix(KKCopy.customInstructionsLimit))
                        }
                    }
                let count = preferences.customInstructions.count
                let limit = KKCopy.customInstructionsLimit
                Text("\(count.formatted()) / \(limit.formatted()) characters")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(count >= limit ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("\(count.formatted()) of \(limit.formatted()) characters used")
            } header: {
                Text("Custom instructions")
            } footer: {
                Text("Added to kk's system prompt for every question, including follow-ups. Saves automatically.")
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
                Image(nsImage: preferences.iconStyle.image ?? NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
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
                    HStack(spacing: 8) {
                        Text("App icon").font(.callout).foregroundStyle(.secondary)
                        Picker("App icon", selection: $preferences.iconStyle) {
                            ForEach(AppIconStyle.allCases) { style in Text(style.title).tag(style) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 150)
                        .help("Changes the icon in About and the Dock. Finder uses the bundled dark icon.")
                    }
                    .padding(.top, 4)
                }
            }

            HStack(alignment: .center, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Markdown, code, tables, math, and diagrams", systemImage: "textformat")
                    Label("Screenshots and attachments stay in memory", systemImage: "rectangle.on.rectangle")
                    Label("Requests go directly to your API provider", systemImage: "network")
                    Label("No saved conversations or analytics", systemImage: "lock.shield")
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

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
