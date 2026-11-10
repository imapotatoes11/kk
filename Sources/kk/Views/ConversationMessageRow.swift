import SwiftUI

struct ConversationMessageRow: View {
    let message: ChatMessage
    @ObservedObject var chat: ChatController
    @ObservedObject var preferences: Preferences
    let onCopy: () -> Void
    @State private var selectedVersion: Int?
    @State private var hovered = false
    private enum HistoryControl: Hashable { case previous, next }
    @FocusState private var focusedHistory: HistoryControl?

    private var shown: ChatMessage { message.displayingVersion(selectedVersion) }
    private var versionIndex: Int { selectedVersion ?? message.previousVersions.count }

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
            if chat.editingMessageID == message.id {
                InlinePromptEdit(chat: chat, preferences: preferences)
            } else if message.role == .user {
                UserMessageBubble(text: shown.content, textSize: preferences.answerTextSize.points, attachments: message.attachments,
                    endpointHost: chat.endpointHost, isInferred: shown.isInferred)
                if shown.isInferred {
                    Text("Prompt revised to fit the earlier change")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } else {
                AssistantMessageView(message: shown,
                    isStreaming: chat.isRevising ? !message.isComplete : chat.isStreaming && message.id == chat.messages.last?.id,
                    preferences: preferences, onCopy: onCopy,
                    onRetry: message.isComplete ? { chat.retry(responseID: message.id) } : nil,
                    onEdit: message.isComplete ? { chat.beginEditing(responseID: message.id) } : nil,
                    actionsDisabled: chat.isStreaming || chat.editingMessageID != nil)
                if message.id != chat.visibleMessages.last?.id { Divider() }
            }
            if !message.previousVersions.isEmpty && chat.editingMessageID != message.id {
                HStack(spacing: 8) {
                    Button("‹ Prev") { selectedVersion = max(0, versionIndex - 1) }
                        .accessibilityLabel("Previous version")
                        .disabled(versionIndex == 0)
                        .focused($focusedHistory, equals: .previous)
                    Text("\(versionIndex + 1)/\(message.previousVersions.count + 1)").monospacedDigit()
                    Button("Next ›") {
                        let next = versionIndex + 1
                        selectedVersion = next >= message.previousVersions.count ? nil : next
                    }
                    .accessibilityLabel("Next version")
                    .disabled(selectedVersion == nil)
                    .focused($focusedHistory, equals: .next)
                    if selectedVersion != nil { Text("Previous version").foregroundStyle(.secondary) }
                }
                .font(.system(size: 11))
                .buttonStyle(.borderless)
                .opacity(hovered || selectedVersion != nil || focusedHistory != nil ? 1 : 0)
                .disabled(chat.isRevising)
                .help("Browse earlier versions. Copy, retry, edit, and follow-ups use the newest version.")
            }
        }
        .onHover { hovered = $0 }
        .onChange(of: message.previousVersions.count) { _, _ in selectedVersion = nil }
        .onChange(of: chat.isRevising) { _, revising in if revising { selectedVersion = nil } }
    }
}

struct InlinePromptEdit: View {
    @ObservedObject var chat: ChatController
    @ObservedObject var preferences: Preferences
    @State private var height: CGFloat = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Edit prompt").font(.caption).foregroundStyle(.secondary)
            PromptEditor(text: $chat.editedPrompt, isDisabled: false, onSubmit: chat.sendEdit,
                onCancel: chat.cancelEditing, registersAsComposer: false, accentColor: preferences.accent.nsColor,
                onHeightChange: { height = min(180, max(60, $0)) })
                .frame(height: height)
                .accessibilityLabel("Edit previous prompt")
            HStack {
                Text("Return to send · Shift + Return for a new line").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Button("Cancel", action: chat.cancelEditing)
                Button("Send", action: chat.sendEdit).disabled(!chat.canSendEdit)
            }
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.5)))
    }
}
