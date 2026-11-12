import SwiftUI

struct AdvancedSettingsView: View {
    @ObservedObject var preferences: Preferences
    @State private var parameterDraft = "{}"

    private var parameterError: String? { InferenceParameters.validationMessage(parameterDraft) }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $parameterDraft)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(height: 112)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Custom inference parameters as JSON")
                HStack(alignment: .top) {
                    if let parameterError {
                        Label(parameterError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.caption)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(parameterDraft == preferences.customInferenceParameters ? "Applied to every request" : "Unapplied changes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Apply") { preferences.customInferenceParameters = parameterDraft }
                        .disabled(parameterError != nil || parameterDraft == preferences.customInferenceParameters)
                }
            } header: {
                Text("Custom inference parameters")
            } footer: {
                Text("Enter a JSON object, for example {\"temperature\": 0.7, \"max_tokens\": 4096}. Supports numbers, strings, booleans, arrays, and nested objects. Sent to your endpoint with every question and repair request. Custom reasoning_effort overrides Inference, including automatic disabling. kk manages model, messages, streaming, and response format. Empty {} uses provider defaults.")
            }

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
                Toggle("Wrap long LaTeX equations", isOn: $preferences.wrapLaTeX)
                Toggle("Fix equations that don't render", isOn: $preferences.repairMath)
            } header: {
                Text("Math")
            } footer: {
                Text("Wrapping breaks long display equations at operators to fit the chat width; fractions, matrices, and other expressions that can't be split safely still scroll horizontally. kk converts common LaTeX its renderer lacks, like \\pmod and \\operatorname, on your Mac. If an equation still can't be drawn, kk shows its source and asks your model once for a corrected version after the answer finishes; this sends the equation and error to your endpoint. Copied equations stay as written unless they were fixed.")
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
                HStack {
                    Text("Expand chat to fit")
                    Spacer()
                    AnnotationShortcutRecorder(bindings: $preferences.windowBindings, action: "expand")
                        .frame(width: 140)
                        .help("Works in the chat window. Press Delete while recording to disable.")
                }
                HStack {
                    Text("Maximum expanded width")
                        .fixedSize()
                    Spacer(minLength: 20)
                    Slider(value: Binding(get: { Double(preferences.expandWidthPercent) },
                        set: { preferences.expandWidthPercent = Int($0.rounded()) }), in: 20...60, step: 1)
                        .frame(minWidth: 180, maxWidth: .infinity)
                        .accessibilityLabel("Maximum expanded width as a percentage of the screen")
                    Text("\(preferences.expandWidthPercent)%").monospacedDigit().frame(width: 40, alignment: .trailing)
                }
                Toggle("Keep popup above other windows", isOn: $preferences.alwaysOnTop)
                Toggle("Snap to default position", isOn: $preferences.snapToDefaultPosition)
                Toggle("Focus kk when an answer finishes", isOn: $preferences.focusOnAnswerComplete)
            } header: {
                Text("Window")
            } footer: {
                Text("Assign an optional shortcut to expand the chat to fit its contents within the display. Unassigned by default. Drag near the default position to snap either axis; guides appear while aligned. Turn off focusing to keep typing in another app while kk answers.")
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
        .onAppear { parameterDraft = preferences.customInferenceParameters }
        .onChange(of: preferences.customInferenceParameters) { _, value in parameterDraft = value }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
