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
    var canSend: Bool {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isStreaming, !isPreparingScreen else { return false }
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
        guard !text.isEmpty else { return }

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

        let requestMessages = ChatRequestBuilder.messages(
            for: messages,
            firstImage: nil,
            appendingUserText: text,
            appendingImage: image,
            additionalImages: image == nil ? [] : additionalScreenData
        )
        let request = ChatCompletionRequest(model: configuration.model, messages: requestMessages, stream: true)

        currentGenerationTask?.cancel()
        let generationID = UUID()
        activeGenerationID = generationID
        prompt = ""
        messages.append(ChatMessage(role: .user, content: text, screenData: image, additionalScreenData: image == nil ? [] : additionalScreenData, screenNames: image == nil ? [] : capturedScreenNames))
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
        send(text: lastUser.content, configuration: configuration)
    }

    var isMultiTurn: Bool { messages.filter { $0.role == .user }.count >= 2 }

    var clipboardTranscript: String {
        messages.filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "## \($0.role == .user ? "You" : "kk")\n\n\($0.content)" }
            .joined(separator: "\n\n")
    }

    private func finishThinking() {
        guard let index = messages.lastIndex(where: { $0.role == .assistant }),
              messages[index].reasoningStartedAt != nil,
              messages[index].reasoningEndedAt == nil else { return }
        messages[index].reasoningEndedAt = .now
    }

}
