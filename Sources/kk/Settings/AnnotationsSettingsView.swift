import SwiftUI

struct AnnotationsSettingsView: View {
    @ObservedObject var preferences: Preferences
    var body: some View {
        Form {
            Section {
                Toggle("Annotate screen on activation", isOn: $preferences.annotationsEnabled)
                Toggle("Freeze screen while annotating", isOn: $preferences.freezeScreen)
                    .disabled(!preferences.annotationsEnabled)
            } header: { Text("Screen annotations") } footer: {
                Text("Freeze holds the screen captured when kk opens. Turn it off to draw over the live desktop and capture it when you send. Changes apply the next time you open kk.")
            }
            Section {
                Picker("Default tool", selection: $preferences.annotationTool) {
                    ForEach(AnnotationTool.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Drawing color") {
                    AnnotationColorPicker(selection: $preferences.annotationColor)
                }
                Toggle("Smooth freehand strokes", isOn: $preferences.smoothStrokes)
                Toggle("Delete hovered annotation with Delete key", isOn: $preferences.deleteHoveredAnnotation)
                Toggle("Confirm before discarding marks", isOn: $preferences.confirmDiscard)
                if preferences.confirmDiscard {
                    LabeledContent("Discard threshold") {
                        HStack(spacing: 8) {
                            Slider(value: Binding(get: { Double(preferences.discardSensitivityLevel) }, set: { preferences.discardSensitivityLevel = Int($0.rounded()) }), in: 0...5, step: 1).frame(width: 150)
                            Button { preferences.discardSensitivityLevel = 1 } label: { Image(systemName: "arrow.counterclockwise") }
                                .buttonStyle(.plain).help("Reset discard threshold").accessibilityLabel("Reset discard threshold")
                        }
                    }
                    let sensitivity = DiscardSensitivity.level(preferences.discardSensitivityLevel)
                    Text("Ask at \(sensitivity.strokeCount) strokes or a stroke longer than \(Int(sensitivity.strokeLength)) points.").font(.caption).foregroundStyle(.secondary)
                }
                Picker("Palette position", selection: $preferences.palettePosition) {
                    ForEach(PalettePosition.allCases) { Text($0.title).tag($0) }
                }
                Picker("Line weight", selection: $preferences.annotationLineWidth) {
                    Text("Thin").tag(2)
                    Text("Regular").tag(3)
                    Text("Bold").tag(5)
                }
                .pickerStyle(.segmented)
            } header: { Text("Drawing") } footer: {
                Text("Click a stroke with Eraser to delete the whole mark. Hover a mark and press Delete while the canvas has focus to delete it with any tool. Undo restores deleted marks. Pointer mode lets clicks pass through. Escape closes kk.")
            }
            .disabled(!preferences.annotationsEnabled)
            Section {
                ForEach(AnnotationTool.canvasTools) { tool in
                    LabeledContent(tool.title) { AnnotationShortcutRecorder(bindings: $preferences.annotationBindings, action: tool.rawValue).frame(width: 140, height: 26) }
                }
                LabeledContent("Pointer") { AnnotationShortcutRecorder(bindings: $preferences.annotationBindings, action: "pointer").frame(width: 140, height: 26) }
                LabeledContent("Focus question") { AnnotationShortcutRecorder(bindings: $preferences.annotationBindings, action: "focus").frame(width: 140, height: 26) }
                Picker("Return to drawing", selection: $preferences.annotationReturnKey) {
                    ForEach(AnnotationReturnKey.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                if preferences.annotationReturnKey == .shortcut {
                    LabeledContent("Drawing shortcut") { AnnotationShortcutRecorder(bindings: $preferences.annotationBindings, action: "annotate").frame(width: 140, height: 26) }
                }
                Button("Restore shortcut defaults") { preferences.annotationBindings = AnnotationShortcut.defaults; preferences.annotationReturnKey = .doubleShift }
            } header: { Text("Keyboard shortcuts") } footer: {
                Text("Click to record a key or key combination. Delete clears it; Escape cancels. Tool keys apply on the canvas. Return to drawing works in the question field. Double Shift may overlap with Sticky Keys.")
            }
            Section {
                Label("Annotations are included in the attached screen image.", systemImage: "rectangle.on.rectangle")
                    .font(.callout)
                Text("Marks stay in memory and clear when you close kk. The screen unfreezes when you send your first question or remove the attachment.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20).padding(.vertical, 12)
    }
}

struct AnnotationColorPicker: View {
    @Binding var selection: AnnotationColor
    var body: some View {
        HStack(spacing: 4) {
            ForEach(AnnotationColor.allCases) { color in
                Button { selection = color } label: {
                    Circle().fill(color.color)
                        .overlay { Circle().strokeBorder(.gray.opacity(0.5), lineWidth: 0.5) }
                        .overlay {
                            if selection == color {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(color == .white || color == .yellow ? .black : .white)
                            }
                        }
                        .frame(width: 20, height: 20).padding(4)
                        .overlay { Circle().strokeBorder(selection == color ? Color.primary : .clear, lineWidth: 1) }
                }
                .buttonStyle(.plain).help(color.title)
                .accessibilityLabel(color.title + " drawing color")
                .accessibilityValue(selection == color ? "Selected" : "")
            }
        }
    }
}
