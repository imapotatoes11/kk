import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var preferences: Preferences
    @State private var apiKey = ""
    @State private var hasSavedKey = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("API") {
                TextField("Base URL", text: $preferences.baseURL)
                    .accessibilityLabel("Base URL")
                TextField("Model", text: $preferences.model)
                    .accessibilityLabel("Model")
                SecureField("API key (optional)", text: $apiKey)
                    .accessibilityLabel("API key, optional")
                if hasSavedKey && apiKey.isEmpty {
                    Text("A key is saved in Keychain. Enter a new value to replace it, or click Clear.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Save API key") { saveKey() }
                    Button("Clear") { clearKey() }
                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(20)
        .frame(width: 500, height: 400)
        .navigationTitle("kk Settings")
        .onAppear {
            hasSavedKey = appState.keychain.loadAPIKey()?.isEmpty == false
        }
    }

    private var description: String {
        let configuration = APIConfiguration(baseURL: preferences.baseURL, apiKey: "", model: preferences.model)
        if let host = configuration.host {
            return "kk sends your question and any attached screen image directly to \(host). Screenshots remain in memory and no conversation history or analytics are stored."
        }
        return "kk sends your question and any attached screen image directly to this OpenAI-compatible endpoint. Screenshots remain in memory and no conversation history or analytics are stored."
    }

    private func saveKey() {
        do {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                try appState.keychain.deleteAPIKey()
                hasSavedKey = false
            } else {
                try appState.keychain.saveAPIKey(trimmed)
                hasSavedKey = true
            }
            apiKey = ""
            statusMessage = "Saved"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func clearKey() {
        do {
            try appState.keychain.deleteAPIKey()
            apiKey = ""
            hasSavedKey = false
            statusMessage = "Cleared"
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
