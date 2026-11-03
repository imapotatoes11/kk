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
                Picker("Open popup", selection: $preferences.popupOpeningPosition) {
                    ForEach(PopupOpeningPosition.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Snap to default position", isOn: $preferences.snapToDefaultPosition)
                Picker("Popup material", selection: $preferences.popupMaterial) {
                    ForEach(PopupMaterial.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Keep popup above other windows", isOn: $preferences.alwaysOnTop)
            } header: {
                Text("Popup")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Compact opens small and smoothly expands when you ask. Either layout can be resized.")
                    Text("At cursor opens below the pointer. Drag near the default position to snap either axis; guides appear while aligned.")
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
                Picker("Answer text", selection: $preferences.answerTextSize) {
                    ForEach(AnswerTextSize.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Show model thinking", isOn: $preferences.showThinking)
            } header: {
                Text("Appearance")
            } footer: {
                HStack(alignment: .top, spacing: 16) {
                    Text("Thinking appears when your provider shares it. Appearance and accent apply to both windows.")
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
