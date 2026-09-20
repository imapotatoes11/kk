import AppKit
import SwiftUI

struct ScreenContextView: View {
    @ObservedObject var chat: ChatController
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    if chat.currentPreviewData != nil { chat.togglePreview() }
                } label: {
                    Label(chat.screenContextState.label, systemImage: iconName)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .disabled(chat.currentPreviewData == nil)
                .help(chat.currentPreviewData == nil ? chat.screenContextState.label : "Preview captured screen")

                Spacer(minLength: 4)

                if !chat.hasSubmitted {
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

            if !chat.hasSubmitted {
                Text(destinationText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityLabel(destinationText)
            } else if chat.currentPreviewData == nil {
                Text("Text only")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .popover(isPresented: $chat.isPreviewPresented, arrowEdge: .bottom) {
            ScreenPreviewView(chat: chat)
        }
        .accessibilityElement(children: .contain)
    }

    private var destinationText: String {
        switch chat.screenContextState {
        case .ready, .capturing: "Sends to \(chat.endpointHost) when you ask"
        case .permissionRequired: "Screen access is optional; text-only sending remains available"
        case .failed(let reason): "\(reason) Text-only sending remains available."
        case .disabled: "No screen attached; this question will be text only"
        case .sent: "Sent to \(chat.endpointHost) with your first question"
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

private struct ScreenPreviewView: View {
    @ObservedObject var chat: ChatController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current screen")
                .font(.headline)
            if let data = chat.currentPreviewData, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: UIConstants.previewMaxWidth, maxHeight: UIConstants.previewMaxHeight)
                    .accessibilityLabel("Captured current screen")
            }
            Text(chat.hasSubmitted ? "Sent to \(chat.endpointHost) with your first question" : "Will send to \(chat.endpointHost) when you ask")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if !chat.hasSubmitted {
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
