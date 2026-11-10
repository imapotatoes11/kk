import AppKit
import CoreGraphics
import Foundation

@MainActor
final class ChatController: ObservableObject {
    @Published var prompt = ""
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var editingMessageID: UUID?
    @Published var editedPrompt = ""
    @Published private(set) var revisionPreview: [ChatMessage]?
    @Published private(set) var revisionProgress: String?
    @Published private(set) var revisionNotice: String?
    private var revisionTask: Task<Void, Never>?
    private var revisionID = UUID()
    private var failedRevision: ConversationRevisionRequest?
    var isRevising: Bool { revisionProgress != nil }
    var composerDisabled: Bool { editingMessageID != nil || isRevising || isPreparingScreen }
    var visibleMessages: [ChatMessage] { revisionPreview ?? messages }

    @Published private(set) var screenContextState: ScreenContextState = .disabled
    @Published private(set) var generationState: GenerationState = .idle
    @Published var isPreviewPresented = false
    @Published private(set) var isPreparingScreen = false
    var onCaptureReady: ((ScreenSnapshot) -> Void)?
    var onRemoveScreen: (() -> Bool)?
    var onAnnotate: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onPrepareFollowUp: (() -> Void)?
    var preparePreview: ((Data) -> Data)?
    @Published private var annotatedPreviewData: Data?
    var prepareAdditionalScreens: (() async throws -> [Data])?
    @Published private(set) var additionalScreenData: [Data] = []
    @Published private(set) var capturedScreenNames: [String] = []
    private var captureAdditionalScreens: [NSScreen] = []
    var prepareScreen: ((Data) async throws -> Data)?
    var onPickFiles: (() -> Void)?
    @Published private(set) var pendingAttachments: [Attachment] = []
    @Published var isDropTargeted = false
    @Published private(set) var attachmentNotice: String?
    private var attachmentTasks: [UUID: Task<Void, Never>] = [:]
    private var attachmentNoticeTask: Task<Void, Never>?
    let diagramRepairs = MermaidRepairStore()
    /// Returns the Mermaid parser's error, or nil for a valid diagram. Replaceable in tests.
    var validateDiagram: @MainActor (String) async -> String? = { await MermaidRenderer.shared.validate($0) }
    private var diagramTasks: [UUID: Task<Void, Never>] = [:]
    private var currentPreparationTask: Task<Void, Never>?
    private var activePreparationID = UUID()

    let preferences: Preferences

    private let keychain: APIKeyStoring
    private let captureService: ScreenCaptureService
    private let captureSnapshot: @Sendable (CGDirectDisplayID?) async throws -> ScreenSnapshot
    private let apiClient: OpenAICompatibleClient
    private var currentCaptureTask: Task<Void, Never>?
    private var currentGenerationTask: Task<Void, Never>?
    private var activeGenerationID = UUID()
    private var activeCaptureID = UUID()
    var screenCaptureSuspended = false
    private var captureScreen: NSScreen?
    private var captureDeniedWithGrantedPreflight = false

    var hasSubmitted: Bool { !messages.isEmpty }
    var isStreaming: Bool { generationState.isStreaming }
    var hasPromptText: Bool { !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var hasProcessingAttachments: Bool { pendingAttachments.contains(where: \.isProcessing) }
    var readyAttachments: [Attachment] { pendingAttachments.filter(\.isReady) }
    /// Attachments can be sent without a question when that is enabled in Settings → Advanced.
    var canSend: Bool {
        guard !composerDisabled, hasPromptText || (preferences.allowAttachmentOnlySend && !readyAttachments.isEmpty),
              !hasProcessingAttachments, !isStreaming, !isPreparingScreen else { return false }
        switch screenContextState {
        case .capturing: return false
        default: return true
        }
    }

    var currentPreviewData: Data? { isPreviewPresented ? (annotatedPreviewData ?? screenContextState.previewData) : screenContextState.previewData }

    var currentPreviewImages: [Data] { currentPreviewData.map { [$0] + additionalScreenData } ?? [] }

    var endpointHost: String {
        APIConfiguration(baseURL: preferences.baseURL, apiKey: "", model: preferences.model).host ?? "configured endpoint"
    }

    init(
        preferences: Preferences,
        keychain: APIKeyStoring,
        captureService: ScreenCaptureService,
        apiClient: OpenAICompatibleClient,
        initialScreenContext: ScreenContextState = .disabled,
        capture: (@Sendable (CGDirectDisplayID?) async throws -> ScreenSnapshot)? = nil
    ) {
        self.preferences = preferences
        self.keychain = keychain
        self.captureService = captureService
        self.captureSnapshot = capture ?? { displayID in try await captureService.captureSnapshot(displayID: displayID) }
        self.apiClient = apiClient
        self.screenContextState = initialScreenContext
    }

    func reset() {
        cancelRevision()
        revisionNotice = nil
        failedRevision = nil
        editingMessageID = nil
        editedPrompt = ""
        currentPreparationTask?.cancel()
        currentPreparationTask = nil
        activePreparationID = UUID()
        isPreparingScreen = false
        currentCaptureTask?.cancel()
        currentGenerationTask?.cancel()
        currentCaptureTask = nil
        currentGenerationTask = nil
        activeGenerationID = UUID()
        activeCaptureID = UUID()
        captureScreen = nil
        captureAdditionalScreens = []
        additionalScreenData = []
        capturedScreenNames = []
        captureDeniedWithGrantedPreflight = false
        cancelAttachmentTasks()
        diagramTasks.values.forEach { $0.cancel() }
        diagramTasks = [:]
        diagramRepairs.reset()
        pendingAttachments = []
        isDropTargeted = false
        attachmentNotice = nil
        prompt = ""
        messages = []
        screenContextState = .disabled
        generationState = .idle
        isPreviewPresented = false
        annotatedPreviewData = nil
    }

    func dismiss() {
        reset()
    }

    func beginCapture(for screen: NSScreen, additionalScreens: [NSScreen] = []) {
        guard !screenCaptureSuspended else { return }
        currentCaptureTask?.cancel()
        captureScreen = screen
        captureAdditionalScreens = additionalScreens
        additionalScreenData = []
        annotatedPreviewData = nil
        isPreviewPresented = false
        capturedScreenNames = ([screen] + additionalScreens).map(\.localizedName)
        let captureID = UUID()
        activeCaptureID = captureID
        guard captureService.hasPassiveAccess, !captureDeniedWithGrantedPreflight else {
            screenContextState = .permissionRequired
            return
        }
        screenContextState = .capturing
        let displayID = DisplayResolver.displayID(for: screen)
        let additionalIDs = additionalScreens.map { DisplayResolver.displayID(for: $0) }
        currentCaptureTask = Task { [weak self, captureService, captureSnapshot] in
            do {
                let snapshot = try await captureSnapshot(displayID)
                var additional: [Data] = []
                for id in additionalIDs {
                    try Task.checkCancellation()
                    additional.append(try await captureSnapshot(id).data)
                }
                try Task.checkCancellation()
                guard let self, self.activeCaptureID == captureID else { return }
                self.additionalScreenData = additional
                self.screenContextState = .ready(snapshot.data)
                self.onCaptureReady?(snapshot)
            } catch is CancellationError {
                return
            } catch let error as KKError {
                guard let self, !Task.isCancelled, self.activeCaptureID == captureID else { return }
                if case .screenCapturePermission = error {
                    // A disagreement between the APIs must not turn polling into repeated requests.
                    self.captureDeniedWithGrantedPreflight = captureService.hasPassiveAccess
                    self.screenContextState = .permissionRequired
                } else {
                    self.screenContextState = .failed(error.localizedDescription)
                }
            } catch {
                guard let self, !Task.isCancelled, self.activeCaptureID == captureID else { return }
                self.screenContextState = .failed(error.localizedDescription)
            }
        }
    }

    func removeScreen() {
        guard !isStreaming, !isPreparingScreen else { return }
        guard onRemoveScreen?() ?? true else { return }
        annotatedPreviewData = nil
        currentCaptureTask?.cancel()
        currentCaptureTask = nil
        activeCaptureID = UUID()
        captureScreen = nil
        captureAdditionalScreens = []
        additionalScreenData = []
        capturedScreenNames = []
        isPreviewPresented = false
        screenContextState = .disabled
    }

    func suspendCaptureForPermissionSetup() {
        screenCaptureSuspended = true
        currentCaptureTask?.cancel()
        currentCaptureTask = nil
        activeCaptureID = UUID()
    }

    func requestScreenAccess() {
        captureDeniedWithGrantedPreflight = false
        _ = captureService.requestAccess()
        resumeCaptureIfPermitted()
    }

    func resumeCaptureIfPermitted() {
        guard !screenCaptureSuspended, !isStreaming, case .permissionRequired = screenContextState,
              captureService.hasPassiveAccess, let screen = captureScreen else { return }
        beginCapture(for: screen, additionalScreens: captureAdditionalScreens)
    }

    func refreshScreenAccess() async {
        guard !screenCaptureSuspended, !isStreaming, captureScreen != nil, case .permissionRequired = screenContextState else { return }
        if await captureService.hasAccess() { resumeCaptureIfPermitted() }
    }

    func openSystemSettings() {
        captureService.openSystemSettings()
    }

    func togglePreview() {
        guard let data = screenContextState.previewData, !isPreparingScreen else { return }
        if isPreviewPresented {
            isPreviewPresented = false
            annotatedPreviewData = nil
        } else {
            annotatedPreviewData = preparePreview?(data)
            isPreviewPresented = true
        }
    }

    func submit() {
        guard canSend else { return }
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        let configuration = APIConfiguration(
            baseURL: preferences.baseURL,
            apiKey: keychain.loadAPIKey() ?? "",
            model: preferences.model
        )

        do {
            _ = try configuration.validated()
        } catch let error as KKError {
            generationState = .error(error)
            return
        } catch {
            generationState = .error(.invalidBaseURL)
            return
        }

        if case .ready(let data) = screenContextState, let prepareScreen {
            isPreparingScreen = true
            let id = UUID()
            activePreparationID = id
            let retainedAdditional = additionalScreenData
            let prepareAdditional = prepareAdditionalScreens
            currentPreparationTask = Task { [weak self] in
                do {
                    // Refresh other displays first, so a failure cannot clear unsent marks.
                    let additional = try await prepareAdditional?() ?? retainedAdditional
                    try Task.checkCancellation()
                    let prepared = try await prepareScreen(data)
                    try Task.checkCancellation()
                    guard let self, self.activePreparationID == id else { return }
                    self.isPreparingScreen = false
                    self.currentPreparationTask = nil
                    self.additionalScreenData = additional
                    self.screenContextState = .ready(prepared)
                    self.send(text: text, configuration: configuration)
                } catch {
                    guard let self, self.activePreparationID == id else { return }
                    self.isPreparingScreen = false
                    self.currentPreparationTask = nil
                    if error is CancellationError { return }
                    self.generationState = .error((error as? KKError) ?? .screenCaptureFailed(error.localizedDescription))
                }
            }
            return
        }
        send(text: text, configuration: configuration)
    }

    private func send(text: String, configuration: APIConfiguration) {
        isPreviewPresented = false
        annotatedPreviewData = nil
        failedRevision = nil
        revisionNotice = nil
        onSubmit?()
        let image: Data?
        if case .ready(let data) = screenContextState {
            image = data
            screenContextState = .sent(data)
        } else { image = nil }

        let attachments = readyAttachments
        cancelAttachmentTasks()
        pendingAttachments = []
        let requestMessages = ChatRequestBuilder.messages(
            for: messages,
            firstImage: nil,
            appendingUserText: text,
            appendingImage: image,
            additionalImages: image == nil ? [] : additionalScreenData,
            appendingAttachments: attachments,
            systemPrompt: KKCopy.systemPrompt(diagrams: preferences.renderDiagrams)
        )
        let request = ChatCompletionRequest(model: configuration.model, messages: requestMessages, stream: true)

        currentGenerationTask?.cancel()
        let generationID = UUID()
        activeGenerationID = generationID
        prompt = ""
        messages.append(ChatMessage(role: .user, content: text, screenData: image, additionalScreenData: image == nil ? [] : additionalScreenData, screenNames: image == nil ? [] : capturedScreenNames, attachments: attachments))
        let assistantID = UUID()
        var assistant = ChatMessage(id: assistantID, role: .assistant, content: "")
        assistant.generationStartedAt = .now
        assistant.isComplete = false
        messages.append(assistant)
        generationState = .streaming

        currentGenerationTask = Task { [weak self, apiClient] in
            defer {
                if self?.activeGenerationID == generationID {
                    self?.finishThinking()
                    self?.onPrepareFollowUp?()
                }
            }
            do {
                for try await delta in apiClient.streamCompletion(request: request, configuration: configuration) {
                    try Task.checkCancellation()
                    guard let self else { return }
                    guard self.activeGenerationID == generationID else { return }
                    if let index = self.messages.firstIndex(where: { $0.id == assistantID }) {
                        switch delta {
                        case .content(let text):
                            if self.messages[index].reasoningStartedAt != nil && self.messages[index].reasoningEndedAt == nil {
                                self.messages[index].reasoningEndedAt = .now
                            }
                            self.messages[index].content.append(text)
                        case .reasoning(let text):
                            if self.messages[index].reasoningStartedAt == nil { self.messages[index].reasoningStartedAt = .now }
                            self.messages[index].reasoning.append(text)
                        }
                    }
                }
                guard let self else { return }
                guard self.activeGenerationID == generationID else { return }
                if let index = self.messages.firstIndex(where: { $0.id == assistantID }) { self.messages[index].isComplete = true }
                self.generationState = .completed
                self.currentGenerationTask = nil
                self.checkDiagrams(in: assistantID)
            } catch is CancellationError {
                guard let self else { return }
                guard self.activeGenerationID == generationID else { return }
                self.generationState = .completed
                self.currentGenerationTask = nil
            } catch let error as KKError {
                guard let self else { return }
                guard self.activeGenerationID == generationID else { return }
                self.generationState = .error(error)
                self.currentGenerationTask = nil
            } catch let error as URLError {
                guard let self else { return }
                guard self.activeGenerationID == generationID else { return }
                self.generationState = .error(.network(error.localizedDescription))
                self.currentGenerationTask = nil
            } catch {
                guard let self else { return }
                guard self.activeGenerationID == generationID else { return }
                self.generationState = .error(.streamFailed(error.localizedDescription))
                self.currentGenerationTask = nil
            }
        }
    }

    func stop() {
        if isRevising {
            cancelRevision()
            revisionNotice = "Revision cancelled. The original conversation was kept."
            failedRevision = nil
            generationState = .completed
            for message in messages where message.role == .assistant { checkDiagrams(in: message.id) }
            return
        }
        guard isStreaming else { return }
        let stoppedID = messages.last(where: { $0.role == .assistant })?.id
        defer { if let stoppedID { checkDiagrams(in: stoppedID) } }
        finishThinking()
        activeGenerationID = UUID()
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        generationState = .completed
        onPrepareFollowUp?()
    }

    func retry() {
        if let failedRevision { startRevision(failedRevision); return }
        if !hasSubmitted { submit(); return }
        guard let lastUser = messages.last(where: { $0.role == .user }) else { return }
        guard !isStreaming, !composerDisabled else { return }
        let configuration = APIConfiguration(baseURL: preferences.baseURL, apiKey: keychain.loadAPIKey() ?? "", model: preferences.model)
        do { _ = try configuration.validated() }
        catch { generationState = .error((error as? KKError) ?? .invalidBaseURL); return }
        currentCaptureTask?.cancel()
        activeCaptureID = UUID()
        if let lastIndex = messages.lastIndex(where: { $0.role == .assistant }) {
            diagramTasks.removeValue(forKey: messages[lastIndex].id)?.cancel()
            messages.remove(at: lastIndex)
        }
        if messages.last?.role == .user { messages.removeLast() }
        capturedScreenNames = lastUser.screenNames
        additionalScreenData = lastUser.additionalScreenData
        screenContextState = lastUser.screenData.map(ScreenContextState.ready) ?? .disabled
        cancelAttachmentTasks()
        pendingAttachments = lastUser.attachments
        send(text: lastUser.content, configuration: configuration)
    }

    var isMultiTurn: Bool { messages.filter { $0.role == .user }.count >= 2 }

    var clipboardTranscript: String {
        messages.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.attachments.isEmpty }
            .map { message in
                let attached = message.attachments.map { "_Attached: \($0.filename) (\($0.detail))_" }
                let body = ([message.content] + attached).filter { !$0.isEmpty }.joined(separator: "\n\n")
                return "## \(message.role == .user ? "You" : "kk")\n\n\(body)"
            }
            .joined(separator: "\n\n")
    }

    // MARK: - Conversation revisions

    func userIndex(forResponse responseID: UUID) -> Int? {
        guard let index = messages.firstIndex(where: { $0.id == responseID }), index > 0,
              messages[index].role == .assistant, messages[index - 1].role == .user else { return nil }
        return index - 1
    }

    func beginEditing(responseID: UUID) {
        guard !isStreaming, !composerDisabled, let index = userIndex(forResponse: responseID), messages[index + 1].isComplete else { return }
        failedRevision = nil
        editedPrompt = messages[index].content
        editingMessageID = messages[index].id
    }

    func cancelEditing() {
        editingMessageID = nil
        editedPrompt = ""
    }

    var canSendEdit: Bool {
        guard let id = editingMessageID, let user = messages.first(where: { $0.id == id }) else { return false }
        return !editedPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !user.attachments.isEmpty
    }

    func sendEdit() {
        guard canSendEdit, let id = editingMessageID,
              let index = messages.firstIndex(where: { $0.id == id }), index + 1 < messages.count else { return }
        startRevision(ConversationRevisionRequest(responseID: messages[index + 1].id, editedPrompt: editedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    func retry(responseID: UUID) {
        guard !isStreaming, !composerDisabled, let index = userIndex(forResponse: responseID), messages[index + 1].isComplete else { return }
        startRevision(ConversationRevisionRequest(responseID: responseID, editedPrompt: nil))
    }

    private func cancelRevision() {
        revisionID = UUID()
        revisionTask?.cancel()
        revisionTask = nil
        revisionPreview = nil
        revisionProgress = nil
    }

    private func startRevision(_ operation: ConversationRevisionRequest) {
        guard !isStreaming, !isRevising, !isPreparingScreen, let start = userIndex(forResponse: operation.responseID) else { return }
        let configuration = APIConfiguration(baseURL: preferences.baseURL, apiKey: keychain.loadAPIKey() ?? "", model: preferences.model)
        do { _ = try configuration.validated() }
        catch { generationState = .error((error as? KKError) ?? .invalidBaseURL); return }
        let original = messages
        // Pause diagram repair before taking over these messages. A late repair must not
        // overwrite a revision or mutate the source branch during the transaction.
        for message in original { diagramTasks.removeValue(forKey: message.id)?.cancel() }
        diagramRepairs.reset()
        cancelEditing()
        failedRevision = nil
        let id = UUID()
        revisionID = id
        revisionNotice = nil
        revisionProgress = "Revising answer…"
        revisionPreview = original
        generationState = .streaming
        revisionTask = Task { [weak self, apiClient] in
            guard let self else { return }
            var revised = original
            var assessor = ConversationRevision.Assessor(client: apiClient, configuration: configuration)
            do {
                if let prompt = operation.editedPrompt {
                    var replacement = revised[start]
                    replacement.content = prompt
                    replacement.isInferred = false
                    revised[start].replace(with: replacement)
                }
                for userIndex in stride(from: start, to: original.count - 1, by: 2) {
                    try Task.checkCancellation()
                    guard self.revisionID == id else { return }
                    let answerIndex = userIndex + 1
                    var needsAnswer = true
                    if userIndex > start {
                        self.revisionProgress = "Checking later turn \(userIndex / 2 + 1)…"
                        let assessment = try await assessor.assess(original: original, revised: revised, userIndex: userIndex)
                        if assessment.prompt != original[userIndex].content {
                            var replacement = revised[userIndex]
                            replacement.content = assessment.prompt
                            replacement.isInferred = true
                            revised[userIndex].replace(with: replacement)
                        }
                        needsAnswer = assessment.regenerateAnswer || !original[answerIndex].isComplete
                    }
                    guard self.revisionID == id else { return }
                    if needsAnswer {
                        self.revisionProgress = userIndex == start ? "Revising answer…" : "Revising later answer \(userIndex / 2 + 1)…"
                        var answer = ChatMessage(id: original[answerIndex].id, role: .assistant, content: "")
                        answer.isComplete = false
                        answer.generationStartedAt = .now
                        let request = ChatCompletionRequest(model: configuration.model, messages: ChatRequestBuilder.messages(for: Array(revised[...userIndex]), firstImage: nil, systemPrompt: KKCopy.systemPrompt(diagrams: self.preferences.renderDiagrams)), stream: true)
                        for try await delta in apiClient.streamCompletion(request: request, configuration: configuration) {
                            try Task.checkCancellation()
                            guard self.revisionID == id else { return }
                            switch delta {
                            case .content(let text):
                                if answer.reasoningStartedAt != nil && answer.reasoningEndedAt == nil { answer.reasoningEndedAt = .now }
                                answer.content += text
                            case .reasoning(let text):
                                if answer.reasoningStartedAt == nil { answer.reasoningStartedAt = .now }
                                answer.reasoning += text
                            }
                            var preview = revised
                            preview[answerIndex] = answer
                            self.revisionPreview = preview
                        }
                        answer.isComplete = true
                        if answer.reasoningStartedAt != nil && answer.reasoningEndedAt == nil { answer.reasoningEndedAt = .now }
                        revised[answerIndex].replace(with: answer)
                    }
                    self.revisionPreview = revised
                }
                try Task.checkCancellation()
                guard self.revisionID == id else { return }
                self.messages = revised
                self.revisionPreview = nil
                self.revisionProgress = nil
                self.revisionTask = nil
                self.generationState = .completed
                for message in revised where message.role == .assistant { self.checkDiagrams(in: message.id) }
            } catch {
                guard self.revisionID == id, !Task.isCancelled else { return }
                self.revisionPreview = nil
                self.revisionProgress = nil
                self.revisionTask = nil
                self.failedRevision = operation
                self.revisionNotice = "Revision failed. The original conversation was kept."
                self.generationState = .error((error as? KKError) ?? .streamFailed("Revision failed. The original conversation was kept. \(error.localizedDescription)"))
                for message in self.messages where message.role == .assistant { self.checkDiagrams(in: message.id) }
            }
        }
    }

    // MARK: - Diagrams

    /// Checks the finished answer's Mermaid diagrams. Each one that fails to parse gets a single
    /// hidden repair request; a valid fix replaces the diagram in the message, so copies and
    /// follow-up requests use it too.
    func checkDiagrams(in messageID: UUID) {
        guard preferences.renderDiagrams, diagramTasks[messageID] == nil,
              let index = messages.firstIndex(where: { $0.id == messageID }), messages[index].role == .assistant else { return }
        var codes: [String] = []
        for block in MermaidExtractor.blocks(in: messages[index].content) {
            let key = MermaidExtractor.key(block.code)
            if !key.isEmpty && !codes.contains(key) && diagramRepairs.status(for: key) == nil { codes.append(key) }
        }
        guard !codes.isEmpty else { return }
        // Mark diagrams first, so views show progress rather than a brief error.
        codes.forEach { diagramRepairs.set($0, .checking) }
        let question = messages[..<index].last(where: { $0.role == .user })?.content ?? ""
        let repair = preferences.repairDiagrams
        let configuration = APIConfiguration(baseURL: preferences.baseURL, apiKey: keychain.loadAPIKey() ?? "", model: preferences.model)
        diagramTasks[messageID] = Task { [weak self] in
            for code in codes {
                guard let self, !Task.isCancelled else { return }
                let validationError = await self.validateDiagram(code)
                guard !Task.isCancelled else { return }
                guard let error = validationError else {
                    self.diagramRepairs.set(code, nil)
                    continue
                }
                guard !Task.isCancelled else { return }
                guard repair else {
                    self.diagramRepairs.set(code, .failed(error))
                    continue
                }
                self.diagramRepairs.set(code, .repairing)
                let fixed = await self.requestDiagramRepair(code: code, error: error, question: question, configuration: configuration)
                guard !Task.isCancelled else { return }
                if let fixed, fixed != code, await self.validateDiagram(fixed) == nil, !Task.isCancelled,
                   self.replaceDiagram(code, with: fixed, in: messageID) {
                    self.diagramRepairs.set(code, nil)
                } else if !Task.isCancelled {
                    self.diagramRepairs.set(code, .failed(error))
                }
            }
            self?.diagramTasks[messageID] = nil
        }
    }

    private func requestDiagramRepair(code: String, error: String, question: String, configuration: APIConfiguration) async -> String? {
        var prompt = "This Mermaid diagram fails to parse.\n\nParser error:\n```\n\(error.prefix(1_000))\n```\n\nDiagram:\n```mermaid\n\(code)\n```"
        let context = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if !context.isEmpty { prompt += "\n\nThe diagram answers this question: \(context.prefix(600))" }
        let request = ChatCompletionRequest(model: configuration.model, messages: [
            APIMessage(role: "system", content: .text(KKCopy.diagramRepairPrompt)),
            APIMessage(role: "user", content: .text(prompt))
        ], stream: true)
        var reply = ""
        do {
            for try await delta in apiClient.streamCompletion(request: request, configuration: configuration) {
                if case .content(let text) = delta { reply += text }
            }
        } catch {
            return nil
        }
        return MermaidExtractor.diagram(inReply: reply)
    }

    private func replaceDiagram(_ original: String, with fixed: String, in messageID: UUID) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == messageID }),
              let updated = MermaidExtractor.replacing(original, with: fixed, in: messages[index].content) else { return false }
        messages[index].content = updated
        return true
    }

    // MARK: - Attachments

    /// Adds files or pasted data. Each one loads in the background; sending waits for them.
    func addAttachments(_ sources: [AttachmentSource]) {
        guard !sources.isEmpty, !isPreparingScreen else { return }
        let room = AttachmentLimits.maxPerTurn - pendingAttachments.count
        if sources.count > room {
            showAttachmentNotice("You can attach up to \(AttachmentLimits.maxPerTurn) files per question.")
        }
        let options = preferences.attachmentOptions
        for source in sources.prefix(max(0, room)) {
            let attachment = Attachment(filename: source.filename, kind: source.expectedKind)
            let id = attachment.id
            pendingAttachments.append(attachment)
            let progress: @Sendable (String) -> Void = { [weak self] message in
                Task { @MainActor in self?.updateAttachment(id) { if $0.isProcessing { $0.status = .processing(message) } } }
            }
            attachmentTasks[id] = Task { [weak self] in
                // A detached task doesn't inherit cancellation, so forward it to stop OCR early.
                let work = Task.detached(priority: .userInitiated) {
                    Result { try AttachmentLoader.load(source, options: options, progress: progress) }
                }
                let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
                guard let self, !Task.isCancelled else { return }
                self.attachmentTasks[id] = nil
                self.updateAttachment(id) { attachment in
                    switch result {
                    case .success(let loaded):
                        attachment.kind = loaded.kind
                        attachment.content = loaded.content
                        attachment.status = .ready
                    case .failure(let error):
                        attachment.status = .failed((error as? LocalizedError)?.errorDescription ?? "Couldn't read this file")
                    }
                }
            }
        }
    }

    /// Returns true when the pasteboard held attachments (files, images, or PDF data).
    @discardableResult
    func addAttachments(from pasteboard: NSPasteboard) -> Bool {
        let sources = AttachmentPasteboard.sources(from: pasteboard)
        if !sources.isEmpty {
            addAttachments(sources)
            return true
        }
        return AttachmentPasteboard.receivePromisedFiles(from: pasteboard) { [weak self] sources in self?.addAttachments(sources) }
    }

    func removeAttachment(_ id: UUID) {
        attachmentTasks[id]?.cancel()
        attachmentTasks[id] = nil
        pendingAttachments.removeAll { $0.id == id }
    }

    func pickFiles() {
        guard !isPreparingScreen else { return }
        onPickFiles?()
    }

    private func updateAttachment(_ id: UUID, _ change: (inout Attachment) -> Void) {
        guard let index = pendingAttachments.firstIndex(where: { $0.id == id }) else { return }
        change(&pendingAttachments[index])
    }

    private func cancelAttachmentTasks() {
        attachmentTasks.values.forEach { $0.cancel() }
        attachmentTasks = [:]
    }

    private func showAttachmentNotice(_ message: String) {
        attachmentNotice = message
        attachmentNoticeTask?.cancel()
        attachmentNoticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.attachmentNotice = nil
        }
    }

    private func finishThinking() {
        guard let index = messages.lastIndex(where: { $0.role == .assistant }),
              messages[index].reasoningStartedAt != nil,
              messages[index].reasoningEndedAt == nil else { return }
        messages[index].reasoningEndedAt = .now
    }

}
