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
    @State private var conversationHeight: CGFloat = 80
    @State private var promptHeight: CGFloat = 24

    private var compactOpening: Bool { preferences.popupSize == .compact && !chat.hasSubmitted }
    private var cornerRadius: CGFloat { 22 }
    private var needsScreenNotice: Bool {
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
                    if hasAttachmentTray {
                        attachmentTray.padding(.horizontal, 16).padding(.bottom, 10)
                    }
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
                    ConversationView(chat: chat, preferences: preferences, onCopyAnswer: onCopyAnswer, onContentHeight: { conversationHeight = $0; resizePanel() })
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
        .environment(\.kkMermaidRepairs, chat.diagramRepairs)
        .environment(\.kkMathRepairs, chat.equationRepairs)
        .environment(\.kkRepairEquation, { [weak chat] source in chat?.repairEquation(source) })
        .environment(\.kkRenderDiagrams, preferences.renderDiagrams)
        .environment(\.kkWrapLaTeX, preferences.wrapLaTeX)
        .environment(\.kkDiagramAccent, preferences.accent.nsColor)
        .task {
            while !Task.isCancelled {
                await chat.refreshScreenAccess()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onAppear {
            panelController.panel?.onEscape = { [weak chat = chat] in
                if chat?.editingMessageID != nil { chat?.cancelEditing() }
                else if chat?.isPreviewPresented == true { chat?.isPreviewPresented = false }
                else { onDismiss() }
            }
            resizePanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in chat.resumeCaptureIfPermitted() }
        .onChange(of: chat.isStreaming) { _, _ in resizePanel() }
        .onChange(of: chat.messages) { _, _ in resizePanel() }
        .onChange(of: preferences.popupSize) { _, _ in resizePanel() }
        .onChange(of: preferences.openingWidth) { _, _ in resizePanel() }
        .onChange(of: preferences.answerTextSize) { _, _ in resizePanel() }
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
            if preferences.showAttachButton { dragGap(4); attachButton(height: 40) }
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
        .modifier(AttachmentDropFeedback(isActive: chat.isDropTargeted, cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .modifier(DraggableInsets(horizontal: 16, vertical: 8))
    }

    private var hasAttachmentTray: Bool { !chat.pendingAttachments.isEmpty || chat.attachmentNotice != nil }

    private var attachmentTray: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !chat.pendingAttachments.isEmpty {
                AttachmentStrip(attachments: chat.pendingAttachments, endpointHost: chat.endpointHost, onRemove: chat.isPreparingScreen ? nil : { chat.removeAttachment($0) })
            }
            if let notice = chat.attachmentNotice {
                Label(notice, systemImage: "info.circle").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func attachButton(height: CGFloat) -> some View {
        Button(action: chat.pickFiles) {
            Image(systemName: "paperclip").frame(width: chat.hasSubmitted ? 32 : 40, height: height).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(chat.isPreparingScreen || chat.pendingAttachments.count >= AttachmentLimits.maxPerTurn)
        .help("Attach images, PDFs, or text files. You can also paste or drop them.")
        .accessibilityLabel("Attach files")
    }

    private var placeholder: String {
        if !chat.pendingAttachments.isEmpty { return chat.pendingAttachments.count == 1 ? "Ask about this file…" : "Ask about these files…" }
        return chat.hasSubmitted ? "Ask a follow-up…" : "Ask a question…"
    }

    private func dragGap(_ width: CGFloat) -> some View {
        PanelDragArea().frame(width: width, height: max(40, promptHeight))
    }

    private var editor: some View {
        PromptEditor(text: $chat.prompt, isDisabled: chat.composerDisabled, onSubmit: chat.submit, accentColor: preferences.accent.nsColor, onHeightChange: { promptHeight = min(120, max(24, $0)) }, onPasteAttachments: { chat.addAttachments(from: $0) })
            .frame(height: promptHeight)
            .overlay(alignment: .topLeading) {
                if chat.prompt.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                        .padding(.top, 2).allowsHitTesting(false)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Question")
    }

    @ViewBuilder private var screenChip: some View {
        if preferences.showPreviewButton && chat.currentPreviewData != nil {
            Button(action: chat.togglePreview) { Image(systemName: "rectangle.on.rectangle").frame(width: 40, height: chat.hasSubmitted ? 32 : 40).contentShape(Rectangle()) }
                .help("\(chat.currentPreviewImages.count) display(s) attached. Sends to \(chat.endpointHost) with your question. Click to preview.")
                .accessibilityLabel("Preview attached screen")
                .contextMenu {
                    Button("Preview screen", action: chat.togglePreview)
                    if !chat.isStreaming { Button("Remove screen", action: chat.removeScreen) }
                }
        }
    }

    private var screenNotice: some View { ScreenContextView(chat: chat, onOpenSettings: onOpenSettings) }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case .error(let error) = chat.generationState { ErrorView(error: error, onRetry: chat.retry, onOpenSettings: onOpenSettings) }
            if hasAttachmentTray { attachmentTray }
            if let notice = chat.revisionNotice {
                Text(notice).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let progress = chat.revisionProgress {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progress).font(.caption).foregroundStyle(.secondary)
                    Text("Changes apply together when finished.").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .bottom, spacing: 0) {
                HStack(spacing: 0) {
                    editor.frame(height: max(24, promptHeight))
                        .modifier(DraggableInsets(horizontal: 0, vertical: max(0, (max(24, promptHeight) - promptHeight) / 2)))
                    if preferences.showAttachButton { attachButton(height: 32) }
                    if chat.hasSubmitted && preferences.annotationsEnabled && !chat.isStreaming {
                        Button { chat.onAnnotate?() } label: { Image(systemName: "pencil.tip").frame(width: 32, height: 32).contentShape(Rectangle()) }
                           .buttonStyle(.plain).disabled(chat.currentPreviewData == nil).help("Annotate this screen").accessibilityLabel("Annotate this screen")
                    }
                    if preferences.showPreviewButton && chat.currentPreviewData != nil {
                        screenChip.buttonStyle(.plain)
                    }
                }
                    .disabled(chat.editingMessageID != nil || chat.isRevising)
                    .opacity(chat.editingMessageID != nil || chat.isRevising ? 0.45 : 1)
                    .frame(minHeight: 32)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
                    .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(Color(nsColor: .separatorColor)).allowsHitTesting(false) }
                    .modifier(AttachmentDropFeedback(isActive: chat.isDropTargeted, cornerRadius: 18))
                    .modifier(DraggableInsets(horizontal: 12, vertical: 4))
                if preferences.showSubmitButton || chat.isStreaming {
                dragGap(10)
                PaletteButton(chat.isStreaming ? "Stop answer" : "Send question", action: {
                    if chat.isStreaming { chat.stop() } else { chat.submit() }
                }) {
                    Image(systemName: chat.isStreaming ? "stop.fill" : "arrow.up")
                        .font(.system(size: 14, weight: .semibold)).frame(width: 40, height: 40).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white)
                .background(Color.accentColor.opacity(chat.isStreaming || chat.canSend ? 1 : 0.45), in: RoundedRectangle(cornerRadius: 12))
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
        let minimum = compactOpening ? compactHeight : (chat.hasSubmitted ? max(220, 45 + footerHeight + 64) : 45 + footerHeight)
        panelController.updateLayout(hasResponse: chat.hasSubmitted, minimumHeight: minimum,
            contentHeight: chat.hasSubmitted ? ConversationLayout.height(content: conversationHeight, chrome: 46 + footerHeight, minimum: minimum, streaming: chat.isStreaming, maximum: preferences.placeInBlankSpace ? .greatestFiniteMagnitude : UIConstants.panelMaxHeight) : nil,
            preferredWidth: chat.hasSubmitted ? ConversationLayout.preferredWidth(messages: chat.messages, minimum: preferences.openingWidth, textSize: preferences.answerTextSize.points) : nil,
            streaming: chat.isStreaming)
    }
}

struct UserMessageBubble: View {
    @Environment(\.colorScheme) private var colorScheme
    let text: String
    var textSize: CGFloat = 14
    var attachments: [Attachment] = []
    var endpointHost: String?
    var isInferred = false
    @State private var availableWidth: CGFloat = 480
    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !text.isEmpty { bubble }
            if !attachments.isEmpty {
                HStack(spacing: 0) {
                    Spacer(minLength: 40)
                    AttachmentStrip(attachments: attachments, alignment: .trailing, endpointHost: endpointHost)
                }
            }
        }
    }

    private var bubble: some View {
        HStack {
            Spacer(minLength: 40)
            ResponseView(markdown: text, isStreaming: false, textSize: textSize)
                // A maximum, not a fixed width, so the bubble can't hold a narrowed window wide.
                .frame(maxWidth: max(4, ConversationLayout.bubbleWidth(text: text, available: availableWidth, fontSize: textSize) - 28))
                .accessibilityLabel("Your question")
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.accentColor.opacity(isInferred ? 0.05 : 0.12), in: RoundedRectangle(cornerRadius: 16))
                .overlay {
                    if isInferred { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.accentColor.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [5, 4])) }
                }
                .accessibilityLabel("Your question: " + text)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = $0 }
    }
}

struct ConversationView: View {
    @ObservedObject var chat: ChatController
    @ObservedObject var preferences: Preferences
    let onCopyAnswer: (String) -> Void
    var onContentHeight: (CGFloat) -> Void = { _ in }
    @State private var isNearBottom = true
    @State private var bottomIsVisible = true
    @State private var isUserScrolling = false
    @State private var contentHeight: CGFloat = 0
    @State private var jumpRequest = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                // Measure the complete content, rather than estimated lazy-row heights.
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(chat.visibleMessages) { message in
                        ConversationMessageRow(message: message, chat: chat, preferences: preferences, onCopy: { onCopyAnswer(message.content) })
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
                    onContentHeight(height)
                }
            }
            .scrollIndicators(.automatic)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - UIConstants.scrollFollowThreshold
            } action: { _, nearBottom in
                bottomIsVisible = nearBottom
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
            .onChange(of: chat.editingMessageID) { _, id in
                guard let id else { return }
                isNearBottom = false
                Task { @MainActor in
                    await Task.yield()
                    if chat.editingMessageID == id { proxy.scrollTo(id, anchor: .top) }
                }
            }
            .onChange(of: chat.messages.last(where: { $0.role == .user })?.id) { _, _ in
                // Sending a question resumes following. An incoming assistant row must
                // preserve the reader's position if they scrolled up meanwhile.
                isNearBottom = true
                proxy.scrollTo("conversation-bottom", anchor: .bottom)
            }
            .overlay(alignment: .bottom) {
                if !bottomIsVisible {
                    Button {
                        isNearBottom = true
                        jumpRequest += 1
                    } label: {
                        Label("Scroll to latest", systemImage: "chevron.down")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .frame(minHeight: 30)
                            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                            .overlay(Capsule().strokeBorder(.primary.opacity(0.15)))
                            .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Scroll to latest")
                    .accessibilityIdentifier("scroll-to-latest")
                    .help("Jump to the most recent message and resume automatic scrolling")
                    .padding(.bottom, 10)
                }
            }
            .task(id: jumpRequest) {
                guard jumpRequest > 0 else { return }
                guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                    proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    return
                }
                // AppKit's rubber-band bounce (after scrolling past the top) can cancel an
                // animated scroll, so retry once, then snap. Stop if the reader scrolls away.
                for attempt in 0..<3 {
                    guard isNearBottom, !bottomIsVisible || attempt == 0 else { return }
                    if attempt < 2 {
                        withAnimation(.smooth(duration: 0.4)) { proxy.scrollTo("conversation-bottom", anchor: .bottom) }
                    } else {
                        proxy.scrollTo("conversation-bottom", anchor: .bottom)
                    }
                    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
                }
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
