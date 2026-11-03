import AppKit
import SwiftUI

struct ScreenContextView: View {
    @ObservedObject var chat: ChatController
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                contextRow
                VStack(alignment: .leading, spacing: 8) {
                    contextLabel
                    contextActions
                }
            }

            if !chat.isStreaming {
                Text(destinationText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(destinationText)
            } else if chat.currentPreviewData == nil {
                Text("Text only")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .accessibilityElement(children: .contain)
    }

    private var contextRow: some View {
        HStack(spacing: 8) {
            contextLabel
            Spacer(minLength: 4)
            contextActions
        }
    }

    private var contextLabel: some View {
        Button {
            if chat.currentPreviewData != nil { chat.togglePreview() }
        } label: {
            Label(chat.screenContextState.label, systemImage: iconName)
                .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .disabled(chat.currentPreviewData == nil)
        .help(chat.currentPreviewData == nil ? chat.screenContextState.label : "Preview captured screen")
    }

    private var contextActions: some View {
        HStack(spacing: 10) {
            if !chat.isStreaming {
                switch chat.screenContextState {
                case .capturing, .ready:
                    Button("Remove screen") { chat.removeScreen() }
                        .buttonStyle(.link)
                        .accessibilityLabel("Remove screen")
                case .permissionRequired:
                    Button("Grant access") { chat.requestScreenAccess() }
                        .buttonStyle(.link)
                    Button("Open System Settings") { chat.openSystemSettings() }
                        .buttonStyle(.link)
                default:
                    EmptyView()
                }
            }
        }
    }

    private var destinationText: String {
        switch chat.screenContextState {
        case .ready, .capturing: "Sends to \(chat.endpointHost) when you ask"
        case .permissionRequired: "Screen access is optional; text-only sending remains available"
        case .failed(let reason): "\(reason) Text-only sending remains available."
        case .disabled: "No screen attached; this question will be text only"
        case .sent: "Sent to \(chat.endpointHost) with your question"
        }
    }

    private var iconName: String {
        switch chat.screenContextState {
        case .capturing: "rectangle.dashed"
        case .ready: "rectangle.on.rectangle"
        case .disabled: "rectangle.slash"
        case .permissionRequired: "lock.rectangle"
        case .failed: "exclamationmark.rectangle"
        case .sent: "checkmark.rectangle"
        }
    }
}

struct ScreenPreviewView: View {
    @ObservedObject var chat: ChatController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(chat.isStreaming ? "Sent screen" : "Screen preview")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(chat.currentPreviewImages.enumerated()), id: \.offset) { index, data in
                        if let image = NSImage(data: data) {
                            if chat.currentPreviewImages.count > 1 {
                                Text(chat.capturedScreenNames.indices.contains(index) ? "\(index + 1). \(chat.capturedScreenNames[index])" : "Display \(index + 1)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Image(nsImage: image).resizable().scaledToFit()
                                .frame(maxWidth: UIConstants.previewMaxWidth, maxHeight: UIConstants.previewMaxHeight)
                                .accessibilityLabel("Captured display \(index + 1)")
                        }
                    }
                }
            }
            .frame(maxHeight: UIConstants.previewMaxHeight)
            if !chat.isStreaming && chat.preferences.annotationsEnabled && !chat.preferences.freezeScreen {
                Text("Live screens refresh when you send.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(chat.isStreaming ? "Sent to \(chat.endpointHost) with your question" : "Will send to \(chat.endpointHost) when you ask")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if !chat.isStreaming {
                Button("Remove screen") {
                    chat.removeScreen()
                    chat.isPreviewPresented = false
                }
                .buttonStyle(.link)
            }
        }
        .padding(14)
        .frame(maxWidth: UIConstants.previewMaxWidth + 28)
    }
}
