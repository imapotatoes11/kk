import AppKit
import SwiftUI

struct PanelRootView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var chat: ChatController
    @ObservedObject var preferences: Preferences
    let panelController: PanelController
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void
    var onCopyAnswer: (String) -> Void = { _ in }
    @State private var footerHeight: CGFloat = 76
    @State private var compactHeight: CGFloat = 64
    @State private var promptHeight: CGFloat = 24

    private var compactOpening: Bool { preferences.popupSize == .compact && !chat.hasSubmitted }
    private var cornerRadius: CGFloat { 22 }
    private var needsScreenNotice: Bool {
        guard !chat.hasSubmitted else { return false }
        switch chat.screenContextState {
        case .permissionRequired, .failed: return true
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if compactOpening {
                VStack(spacing: 0) {
                    launcherBar
                    if needsScreenNotice {
                        screenNotice.padding(.horizontal, 16).padding(.bottom, 12)
                    }
                    if case .error(let error) = chat.generationState {
                        ErrorView(error: error, onRetry: chat.retry, onOpenSettings: onOpenSettings).padding(12)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    guard height > 0, abs(compactHeight - height) > 1 else { return }
                    compactHeight = height
                    resizePanel()
                }
            } else {
                header
                Divider()
                if chat.hasSubmitted {
                    ConversationView(chat: chat, preferences: preferences, onCopyAnswer: onCopyAnswer)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                }
                footer
                    .fixedSize(horizontal: false, vertical: true)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        guard height > 0, abs(footerHeight - height) > 1 else { return }
                        footerHeight = height
                        resizePanel()
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .modifier(PopupSurface(material: preferences.popupMaterial))
        .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
        .tint(preferences.accent.color)
        .accentColor(preferences.accent.color)
        .popover(isPresented: $chat.isPreviewPresented, arrowEdge: .bottom) { ScreenPreviewView(chat: chat) }
        .task {
            while !Task.isCancelled {
                await chat.refreshScreenAccess()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onAppear {
            panelController.panel?.onEscape = { [weak chat = chat] in
                if chat?.isPreviewPresented == true { chat?.isPreviewPresented = false }
                else { onDismiss() }
            }
            resizePanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in chat.resumeCaptureIfPermitted() }
        .onChange(of: chat.messages.count) { _, _ in resizePanel() }
        .onChange(of: preferences.popupSize) { _, _ in resizePanel() }
    }

    private var branding: some View {
        PanelDragArea()
            .overlay(alignment: .leading) { Text("kk").font(.system(size: 15, weight: .semibold)).allowsHitTesting(false) }
            .frame(width: 24, height: 40)
            .help("Drag to move kk")
            .accessibilityLabel("Drag to move kk")
    }

    private var settingsButton: some View {
        Button(action: onOpenSettings) { Image(systemName: "gearshape").foregroundStyle(.primary).frame(width: 40, height: 40).contentShape(Rectangle()) }
            .keyboardShortcut(",", modifiers: .command)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
    }

    private var header: some View {
        HStack(spacing: 0) {
            branding
            PanelDragArea().frame(maxWidth: .infinity).help("Drag to move kk")
            settingsButton
            PanelDragArea().frame(width: 8, height: 40)
            Button(action: onDismiss) { Image(systemName: "xmark").frame(width: 40, height: 40).contentShape(Rectangle()) }
                .help("Close (Escape)").accessibilityLabel("Close popup")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 44)
        .modifier(DraggableInsets(horizontal: 16, vertical: 2))
    }

    private var launcherBar: some View {
        let rowHeight = max(40, promptHeight)
        return HStack(spacing: 0) {
            branding.foregroundStyle(.secondary)
            dragGap(10)
            editor.frame(height: rowHeight)
                .modifier(DraggableInsets(horizontal: 0, vertical: max(0, (rowHeight - promptHeight) / 2)))
            if preferences.showPreviewButton && chat.currentPreviewData != nil { dragGap(4); screenChip }
            if preferences.showSubmitButton {
                dragGap(4)
                Button(action: chat.submit) { Image(systemName: "arrow.turn.down.left").frame(width: 40, height: 40).contentShape(Rectangle()) }
                    .disabled(!chat.canSend).help("Send question (Return)").accessibilityLabel("Send question")
            }
            dragGap(4)
            settingsButton
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .modifier(DraggableInsets(horizontal: 16, vertical: 8))
    }

    private func dragGap(_ width: CGFloat) -> some View {
        PanelDragArea().frame(width: width, height: max(40, promptHeight))
    }

    private var editor: some View {
        PromptEditor(text: $chat.prompt, isDisabled: chat.isStreaming || chat.isPreparingScreen, onSubmit: chat.submit, accentColor: preferences.accent.nsColor, onHeightChange: { promptHeight = min(120, max(24, $0)) })
            .frame(height: promptHeight)
            .overlay(alignment: .topLeading) {
                if chat.prompt.isEmpty {
                    Text(chat.hasSubmitted ? "Ask a follow-up…" : "Ask a question…")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                        .padding(.top, 2).allowsHitTesting(false)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Question")
    }

    @ViewBuilder private var screenChip: some View {
        if preferences.showPreviewButton && chat.currentPreviewData != nil {
            Button(action: chat.togglePreview) { Image(systemName: "rectangle.on.rectangle").frame(width: 40, height: 40).contentShape(Rectangle()) }
                .help("Screen attached. Sends to \(chat.endpointHost) with your question. Click to preview.")
                .accessibilityLabel("Preview attached screen")
                .contextMenu {
                    Button("Preview screen", action: chat.togglePreview)
                    if !chat.hasSubmitted { Button("Remove screen", action: chat.removeScreen) }
                }
        }
    }

    private var screenNotice: some View { ScreenContextView(chat: chat, onOpenSettings: onOpenSettings) }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case .error(let error) = chat.generationState { ErrorView(error: error, onRetry: chat.retry, onOpenSettings: onOpenSettings) }
            HStack(alignment: .bottom, spacing: 0) {
                HStack(spacing: 0) {
                    editor.frame(height: max(40, promptHeight))
                        .modifier(DraggableInsets(horizontal: 0, vertical: max(0, (max(40, promptHeight) - promptHeight) / 2)))
                    if preferences.showPreviewButton && chat.currentPreviewData != nil { dragGap(4); screenChip.buttonStyle(.plain) }
                }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color(nsColor: .separatorColor)).allowsHitTesting(false) }
                    .modifier(DraggableInsets(horizontal: 12, vertical: 10))
                if preferences.showSubmitButton || chat.isStreaming {
                dragGap(10)
                Button {
                    if chat.isStreaming { chat.stop() } else { chat.submit() }
                } label: {
                    Image(systemName: chat.isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: 14, weight: .semibold)).frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.roundedRectangle(radius: 12))
                .disabled(!chat.isStreaming && !chat.canSend)
                .help(chat.isStreaming ? "Stop answer" : "Send question (Return)")
                .accessibilityLabel(chat.isStreaming ? "Stop answer" : "Send question")
                }
            }
            if needsScreenNotice { screenNotice }
        }
        .padding(12)
        .modifier(DraggableInsets(horizontal: 12, vertical: 12))
    }

    private func resizePanel() {
        panelController.updateLayout(hasResponse: chat.hasSubmitted, minimumHeight: compactOpening ? compactHeight : 45 + footerHeight + (chat.hasSubmitted ? 80 : 0))
    }
}

struct UserMessageBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    var body: some View {
        HStack {
            Spacer(minLength: 40)
            ResponseView(markdown: text, isStreaming: false)
                .accessibilityLabel("Your question")
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Your question: " + text)
        }
    }
}

private struct ConversationView: View {
    @ObservedObject var chat: ChatController
    @ObservedObject var preferences: Preferences
    let onCopyAnswer: (String) -> Void
    @State private var isNearBottom = true
    @State private var isUserScrolling = false
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                // Measure the complete content, rather than estimated lazy-row heights.
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(chat.messages) { message in
                        VStack(alignment: .leading, spacing: 10) {
                            if message.role == .user {
                                UserMessageBubble(text: message.content)
                            } else {
                                AssistantMessageView(message: message, isStreaming: chat.isStreaming && message.id == chat.messages.last?.id, preferences: preferences, onCopy: { onCopyAnswer(message.content) })
                                if message.id != chat.messages.last?.id { Divider() }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(message.id)
                    }
                    Color.clear.frame(height: 1).id("conversation-bottom")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { geometry in
                    geometry.size.height
                } action: { height in
                    contentHeight = height
                }
            }
            .scrollIndicators(.automatic)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - UIConstants.scrollFollowThreshold
            } action: { _, nearBottom in
                if isUserScrolling { isNearBottom = nearBottom }
            }
            .onScrollPhaseChange { _, phase, context in
                let wasUserScrolling = isUserScrolling
                isUserScrolling = phase == .interacting || phase == .decelerating || phase == .tracking
                if isUserScrolling || (phase == .idle && wasUserScrolling) {
                    let geometry = context.geometry
                    isNearBottom = geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - UIConstants.scrollFollowThreshold
                }
            }
            .onChange(of: chat.messages.count) { _, _ in
                isNearBottom = true
            }
            .task(id: contentHeight) {
                // Resize the outer panel and finish the content layout before following.
                await Task.yield()
                guard !Task.isCancelled, isNearBottom else { return }
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
        }
    }
}
