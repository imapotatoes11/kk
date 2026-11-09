import SwiftUI

struct CustomizationView: View {
    @ObservedObject var preferences: Preferences

    var body: some View {
        Form {
            Section {
                Picker("Opening size", selection: $preferences.popupSize) {
                    ForEach(PopupSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                if preferences.popupSize == .fullSize {
                    BarWidthControl(title: "Full-size width", level: $preferences.fullWidthLevel, widths: BarWidths.full, defaultLevel: BarWidths.fullDefault)
                } else {
                    BarWidthControl(title: "Compact width", level: $preferences.compactWidthLevel, widths: BarWidths.compact, defaultLevel: BarWidths.compactDefault)
                }
                Picker("Open popup", selection: $preferences.popupOpeningPosition) {
                    ForEach(PopupOpeningPosition.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(preferences.placeInBlankSpace)
                Toggle("Move chat to largest blank space", isOn: $preferences.placeInBlankSpace)
                    .help("Scan this display locally when chat opens and each message is sent. Requires Screen Recording access.")
                Toggle("Snap to default position", isOn: $preferences.snapToDefaultPosition)
                Picker("Popup material", selection: $preferences.popupMaterial) {
                    ForEach(PopupMaterial.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Keep popup above other windows", isOn: $preferences.alwaysOnTop)
                Toggle("Show image preview button", isOn: $preferences.showPreviewButton)
                Toggle("Show submit button", isOn: $preferences.showSubmitButton)
            } header: {
                Text("Popup")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Compact opens small and smoothly expands when you ask. Either layout can be resized.")
                    Text("At cursor opens below the pointer. Drag near the default position to snap either axis; guides appear while aligned.")
                    if preferences.placeInBlankSpace {
                        Text("Blank-space placement scans the chat’s display on open and send, and reduces width and height to fit. Scans stay local. Without Screen Recording access, the normal opening position is used.")
                    }
                    if #unavailable(macOS 26) {
                        Text("Liquid Glass uses translucency on this version of macOS.")
                    }
                    Text("Uses your macOS Reduce Motion and Reduce Transparency settings.")
                }
            }

            Section {
                Picker("Appearance", selection: $preferences.appearance) {
                    ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Accent color") {
                    HStack(spacing: 6) {
                        ForEach(AppAccent.allCases) { accent in
                            AccentSwatch(accent: accent, isSelected: preferences.accent == accent) {
                                preferences.accent = accent
                            }
                        }
                    }
                }
                LabeledContent("Chat text size") {
                    HStack(spacing: 8) {
                        Text("\(Int(preferences.answerTextSize.points)) pt")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 38)
                        Slider(value: Binding(
                            get: { Double(preferences.answerTextSize.points) },
                            set: { preferences.answerTextSize = AnswerTextSize(points: CGFloat($0)) }
                        ), in: AnswerTextSize.range, step: 1)
                            .frame(width: 140)
                            .accessibilityLabel("Chat text size")
                            .accessibilityValue("\(Int(preferences.answerTextSize.points)) points")
                        Button("Reset") { preferences.answerTextSize = .standard }
                            .buttonStyle(.borderless)
                            .disabled(preferences.answerTextSize == .standard)
                            .help("Reset chat text size to the default (14 pt)")
                            .accessibilityLabel("Reset chat text size to default")
                    }
                }
                Toggle("Show model thinking", isOn: $preferences.showThinking)
            } header: {
                Text("Appearance")
            }

            Section {
                Picker("Attach screen", selection: $preferences.captureDisplayMode) {
                    ForEach(CaptureDisplayMode.allCases) { Text($0.title).tag($0) }
                }
            } header: {
                Text("Screen capture")
            } footer: {
                Text("Active uses the focused window’s display; cursor uses the pointer’s display. All attaches a separate image of each display’s visible desktop. Applies to the next capture.")
            }

            Section {
                Toggle("Copy multi-turn chats on dismiss", isOn: $preferences.copyChatOnDismiss)
                Toggle("Confirm before dismissing multi-turn chats", isOn: $preferences.confirmDismissChat)
            } header: {
                Text("Conversations")
            } footer: {
                HStack(alignment: .top, spacing: 16) {
                    Text("Applies after two or more questions. Copies the conversation as Markdown, without screen images or thinking.")
                    Spacer(minLength: 0)
                    Button("Restore defaults") { preferences.resetCustomization() }
                        .help("Reset customization. Your connection and keyboard shortcut stay unchanged.")
                        .fixedSize()
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

private struct AccentSwatch: View {
    let accent: AppAccent
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if accent == .system {
                    Circle()
                        .fill(AngularGradient(colors: [.blue, .purple, .pink, .red, .orange, .yellow, .green, .blue], center: .center))
                } else {
                    Circle().fill(accent.color ?? .primary)
                }
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                }
            }
            .frame(width: 22, height: 22)
            .padding(4)
            .overlay {
                Circle().strokeBorder(isSelected ? Color.primary : Color.clear, lineWidth: 1.5)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(accent == .system ? "Follow the macOS accent color" : accent.title)
        .accessibilityLabel(accent.title + " accent color")
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct BarWidthControl: View {
    let title: String
    @Binding var level: Int
    let widths: [CGFloat]
    let defaultLevel: Int

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text("\(Int(widths[BarWidths.clamp(level)])) pt")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 46)
                Slider(value: Binding(get: { Double(level) }, set: { level = Int($0) }), in: 0...5, step: 1)
                    .frame(width: 140).accessibilityLabel(title)
                Button { level = defaultLevel } label: { Image(systemName: "arrow.counterclockwise") }
                    .buttonStyle(.borderless).help("Reset \(title.lowercased())")
                    .accessibilityLabel("Reset \(title.lowercased())")
            }
        }
    }
}
