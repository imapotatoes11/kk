import AppKit
import CoreGraphics
import Foundation

@MainActor
final class ChatController: ObservableObject {
    @Published var prompt = ""
    @Published private(set) var messages: [ChatMessage] = []
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
        guard hasPromptText || (preferences.allowAttachmentOnlySend && !readyAttachments.isEmpty),
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
            appendingAttachments: attachments
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
                self.generationState = .completed
                self.currentGenerationTask = nil
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
        guard isStreaming else { return }
        finishThinking()
        activeGenerationID = UUID()
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        generationState = .completed
        onPrepareFollowUp?()
    }

    func retry() {
        if !hasSubmitted { submit(); return }
        guard let lastUser = messages.last(where: { $0.role == .user }) else { return }
        guard !isStreaming, !isPreparingScreen else { return }
        let configuration = APIConfiguration(baseURL: preferences.baseURL, apiKey: keychain.loadAPIKey() ?? "", model: preferences.model)
        do { _ = try configuration.validated() }
        catch { generationState = .error((error as? KKError) ?? .invalidBaseURL); return }
        currentCaptureTask?.cancel()
        activeCaptureID = UUID()
        if let lastIndex = messages.lastIndex(where: { $0.role == .assistant }) { messages.remove(at: lastIndex) }
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
