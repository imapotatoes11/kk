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
    var onSubmit: (() -> Void)?
    var preparePreview: ((Data) -> Data)?
    @Published private var annotatedPreviewData: Data?
    var prepareScreen: ((Data) async throws -> Data)?
    private var currentPreparationTask: Task<Void, Never>?
    private var activePreparationID = UUID()

    let preferences: Preferences

    private let keychain: APIKeyStoring
    private let captureService: ScreenCaptureService
    private let apiClient: OpenAICompatibleClient
    private var currentCaptureTask: Task<Void, Never>?
    private var currentGenerationTask: Task<Void, Never>?
    private var firstScreenData: Data?
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

    var endpointHost: String {
        APIConfiguration(baseURL: preferences.baseURL, apiKey: "", model: preferences.model).host ?? "configured endpoint"
    }

    init(
        preferences: Preferences,
        keychain: APIKeyStoring,
        captureService: ScreenCaptureService,
        apiClient: OpenAICompatibleClient,
        initialScreenContext: ScreenContextState = .disabled
    ) {
        self.preferences = preferences
        self.keychain = keychain
        self.captureService = captureService
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
        captureDeniedWithGrantedPreflight = false
        prompt = ""
        messages = []
        screenContextState = .disabled
        generationState = .idle
        isPreviewPresented = false
        annotatedPreviewData = nil
        firstScreenData = nil
    }

    func dismiss() {
        reset()
    }

    func beginCapture(for screen: NSScreen) {
        guard !screenCaptureSuspended else { return }
        currentCaptureTask?.cancel()
        captureScreen = screen
        let captureID = UUID()
        activeCaptureID = captureID
        guard captureService.hasPassiveAccess, !captureDeniedWithGrantedPreflight else {
            screenContextState = .permissionRequired
            return
        }
        screenContextState = .capturing
        let displayID = DisplayResolver.displayID(for: screen)
        currentCaptureTask = Task { [weak self, captureService] in
            do {
                let snapshot = try await captureService.captureSnapshot(displayID: displayID)
                try Task.checkCancellation()
                guard let self, self.activeCaptureID == captureID else { return }
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
        guard !hasSubmitted, !isPreparingScreen else { return }
        guard onRemoveScreen?() ?? true else { return }
        annotatedPreviewData = nil
        currentCaptureTask?.cancel()
        currentCaptureTask = nil
        activeCaptureID = UUID()
        captureScreen = nil
        isPreviewPresented = false
        guard !hasSubmitted else { return }
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
        guard !screenCaptureSuspended, !hasSubmitted, case .permissionRequired = screenContextState,
              captureService.hasPassiveAccess, let screen = captureScreen else { return }
        beginCapture(for: screen)
    }

    func refreshScreenAccess() async {
        guard !screenCaptureSuspended, !hasSubmitted, captureScreen != nil, case .permissionRequired = screenContextState else { return }
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
            currentPreparationTask = Task { [weak self] in
                do {
                    let prepared = try await prepareScreen(data)
                    try Task.checkCancellation()
                    guard let self, self.activePreparationID == id else { return }
                    self.isPreparingScreen = false
                    self.currentPreparationTask = nil
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
        if case .ready(let data) = screenContextState {
            firstScreenData = data
            screenContextState = .sent(data)
        }

        let requestMessages = ChatRequestBuilder.messages(
            for: messages,
            firstImage: firstScreenData,
            appendingUserText: text
        )
        let request = ChatCompletionRequest(model: configuration.model, messages: requestMessages, stream: true)

        currentGenerationTask?.cancel()
        let generationID = UUID()
        activeGenerationID = generationID
        prompt = ""
        messages.append(ChatMessage(role: .user, content: text))
        let assistantID = UUID()
        var assistant = ChatMessage(id: assistantID, role: .assistant, content: "")
        assistant.generationStartedAt = .now
        messages.append(assistant)
        generationState = .streaming

        currentGenerationTask = Task { [weak self, apiClient] in
            defer {
                if self?.activeGenerationID == generationID { self?.finishThinking() }
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
    }

    func retry() {
        if !hasSubmitted { submit(); return }
        guard let lastUser = messages.last(where: { $0.role == .user }) else { return }
        if let lastIndex = messages.lastIndex(where: { $0.role == .assistant }) {
            messages.remove(at: lastIndex)
        }
        prompt = lastUser.content
        if messages.last?.role == .user { messages.removeLast() }
        submit()
    }

    private func finishThinking() {
        guard let index = messages.lastIndex(where: { $0.role == .assistant }),
              messages[index].reasoningStartedAt != nil,
              messages[index].reasoningEndedAt == nil else { return }
        messages[index].reasoningEndedAt = .now
    }

}
