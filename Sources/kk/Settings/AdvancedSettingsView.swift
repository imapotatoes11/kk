import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Toggle("Send attachments without a question", isOn: $preferences.allowAttachmentOnlySend)
                Picker("PDF page images", selection: $preferences.pdfPageImageLimit) {
                    ForEach(AttachmentLimits.pageImageOptions, id: \.self) { count in
                        Text(count == 0 ? "Off" : "First \(count) pages").tag(count)
                    }
                }
            } header: {
                Text("Attachments")
            } footer: {
                Text("Paste, drop, or attach images (including HEIC and WebP), PDFs, and text files. PDFs always send their text, and scanned pages are read with on-device OCR. Page images let vision models see figures and layout; turn them off for text-only models or to send less data. Applies to files you attach next.")
            }

            Section {
                Toggle("Draw Mermaid diagrams", isOn: $preferences.renderDiagrams)
                Toggle("Fix diagrams that don't render", isOn: $preferences.repairDiagrams)
                    .disabled(!preferences.renderDiagrams)
            } header: {
                Text("Diagrams")
            } footer: {
                Text("Answers can include flowcharts, sequence diagrams, and other Mermaid diagrams, drawn on your Mac. If a diagram has a syntax error, kk asks your model once for a corrected version after the answer finishes; this sends the diagram and error to your endpoint. With drawing off, diagrams appear as code and the model isn't asked to make them.")
            }

            Section {
                Toggle("Show attach button", isOn: $preferences.showAttachButton)
                Toggle("Show image preview button", isOn: $preferences.showPreviewButton)
                Toggle("Show submit button", isOn: $preferences.showSubmitButton)
            } header: {
                Text("Popup controls")
            } footer: {
                Text("Paste (⌘V) and drag and drop attach files even when the attach button is hidden.")
            }

            Section {
                Toggle("Keep popup above other windows", isOn: $preferences.alwaysOnTop)
                Toggle("Snap to default position", isOn: $preferences.snapToDefaultPosition)
            } header: {
                Text("Window")
            } footer: {
                Text("Drag near the default position to snap either axis; guides appear while aligned.")
            }

            Section {
                Toggle("Copy multi-turn chats on dismiss", isOn: $preferences.copyChatOnDismiss)
                Toggle("Confirm before dismissing multi-turn chats", isOn: $preferences.confirmDismissChat)
            } header: {
                Text("Conversations")
            } footer: {
                HStack(alignment: .top, spacing: 16) {
                    Text("Applies after two or more questions. Copies the conversation as Markdown, without screen images, attachment contents, or thinking.")
                    Spacer(minLength: 0)
                    Button("Restore defaults") { preferences.resetAdvanced() }
                        .help("Reset Advanced settings. General settings, your connection, and shortcuts stay unchanged.")
                        .fixedSize()
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
