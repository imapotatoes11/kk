import AppKit
import SwiftUI

struct PanelRootView: View {
    @ObservedObject var chat: ChatController
    @ObservedObject var preferences: Preferences
    let panelController: PanelController
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void
    @State private var conversationContentHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.sectionSpacing) {
            if !chat.messages.isEmpty {
                ConversationView(chat: chat) { measuredHeight in
                    guard abs(conversationContentHeight - measuredHeight) > 1 else { return }
                    conversationContentHeight = measuredHeight
                    panelController.resize(height: desiredHeight, animated: !chat.isStreaming)
                }
                    .frame(maxHeight: .infinity)
                    .transition(.opacity)
            }

            if case .error(let error) = chat.generationState {
                ErrorView(error: error, onRetry: chat.retry, onOpenSettings: onOpenSettings)
            }

            HStack(alignment: .bottom, spacing: 8) {
                PromptEditor(
                    text: $chat.prompt,
                    isDisabled: chat.isStreaming,
                    onSubmit: {
                        if chat.isStreaming { chat.stop() } else { chat.submit() }
                    }
                )
                .frame(minHeight: 22, maxHeight: 96)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if chat.prompt.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .allowsHitTesting(false)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Question")

                Button {
                    if chat.isStreaming { chat.stop() } else { chat.submit() }
                } label: {
                    Image(systemName: chat.isStreaming ? "stop.fill" : "arrow.up")
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 8))
                .disabled(chat.isStreaming ? false : !chat.canSend)
                .help(chat.isStreaming ? "Stop answer" : "Send question")
                .accessibilityLabel(chat.isStreaming ? "Stop answer" : "Send question")
            }

            ScreenContextView(chat: chat, onOpenSettings: onOpenSettings)
        }
        .padding(UIConstants.outerPadding)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: UIConstants.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: UIConstants.cornerRadius)
                .stroke(Color(nsColor: .separatorColor).opacity(0.75), lineWidth: 1)
        }
        .onAppear {
            panelController.onEscape = { [weak chat] in
                if chat?.isPreviewPresented == true {
                    chat?.isPreviewPresented = false
                } else {
                    onDismiss()
                }
            }
            panelController.resize(height: desiredHeight)
        }
        .onChange(of: chat.messages.count) { _, _ in
            panelController.resize(height: desiredHeight, animated: !chat.isStreaming)
        }
        .onChange(of: chat.prompt) { _, _ in
            panelController.resize(height: desiredHeight, animated: !chat.isStreaming)
        }
        .onChange(of: chat.generationState.isStreaming) { _, _ in
            panelController.resize(height: desiredHeight, animated: !chat.isStreaming)
        }
        .onChange(of: stateDescription) { _, _ in
            panelController.resize(height: desiredHeight, animated: !chat.isStreaming)
        }
        .animation(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .easeOut(duration: 0.2), value: chat.messages.count)
    }

    private var placeholder: String {
        if chat.hasSubmitted { return "Ask a follow-up…" }
        switch chat.screenContextState {
        case .permissionRequired, .disabled, .failed: return "Ask a question…"
        default: return "Ask about your screen…"
        }
    }

    private var desiredHeight: CGFloat {
        let promptLines = min(5, max(1, chat.prompt.split(separator: "\n", omittingEmptySubsequences: false).count))
        let promptExtra = CGFloat(promptLines - 1) * 18
        if chat.messages.isEmpty {
            return min(UIConstants.panelMaxHeight, 132 + promptExtra + (chat.generationState.isStreaming ? 0 : 0))
        }
        let errorExtra: CGFloat = {
            if case .error = chat.generationState { return 70 }
            return 0
        }()
        return min(UIConstants.panelMaxHeight, max(230, conversationContentHeight + 106 + promptExtra + errorExtra))
    }

    private var stateDescription: String { String(describing: chat.generationState) }
}

private struct ConversationView: View {
    @ObservedObject var chat: ChatController
    let onContentHeightChange: (CGFloat) -> Void
    @State private var isNearBottom = true

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(chat.messages) { message in
                            VStack(alignment: .leading, spacing: 7) {
                                if message.role == .user {
                                    Text(message.content)
                                        .font(.system(size: 14, weight: .medium))
                                        .textSelection(.enabled)
                                        .accessibilityLabel("Your question")
                                } else {
                                    ResponseView(markdown: message.content.isEmpty ? "Thinking…" : message.content, isStreaming: chat.isStreaming)
                                    if message.id == chat.messages.last(where: { $0.role == .assistant })?.id {
                                        Button("Copy") { chat.copyLastAnswer() }
                                            .buttonStyle(.link)
                                            .font(.system(size: 12))
                                            .accessibilityLabel("Copy assistant answer")
                                    }
                                }
                                if message.id != chat.messages.last?.id {
                                    Divider()
                                }
                            }
                            .id(message.id)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("conversation-bottom")
                            .background {
                                GeometryReader { bottom in
                                    Color.clear.preference(
                                        key: ScrollBottomDistanceKey.self,
                                        value: bottom.frame(in: .named("conversation-scroll")).maxY - viewport.size.height
                                    )
                                }
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        GeometryReader { content in
                            Color.clear.preference(
                                key: ConversationContentHeightKey.self,
                                value: content.size.height
                            )
                        }
                    }
                }
                .coordinateSpace(name: "conversation-scroll")
                .scrollIndicators(.automatic)
                .onPreferenceChange(ScrollBottomDistanceKey.self) { distance in
                    isNearBottom = distance <= UIConstants.scrollFollowThreshold
                }
                .onPreferenceChange(ConversationContentHeightKey.self, perform: onContentHeightChange)
                .onChange(of: chat.messages.last?.content) { _, _ in
                    guard chat.isStreaming, isNearBottom else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    }
                }
                .onChange(of: chat.messages.count) { _, _ in
                    guard let id = chat.messages.last?.id else { return }
                    proxy.scrollTo(id, anchor: .bottom)
                    isNearBottom = true
                }
            }
        }
    }
}

private struct ScrollBottomDistanceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ConversationContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
