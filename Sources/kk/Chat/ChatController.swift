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

    let preferences: Preferences

    private let keychain: APIKeyStoring
    private let captureService: ScreenCaptureService
    private let apiClient: OpenAICompatibleClient
    private var currentCaptureTask: Task<Void, Never>?
    private var currentGenerationTask: Task<Void, Never>?
    private var firstScreenData: Data?

    var hasSubmitted: Bool { !messages.isEmpty }
    var isStreaming: Bool { generationState.isStreaming }
    var canSend: Bool {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !isStreaming else { return false }
        switch screenContextState {
        case .capturing: return false
        default: return true
        }
    }

    var currentPreviewData: Data? { screenContextState.previewData }

    var endpointHost: String {
        APIConfiguration(baseURL: preferences.baseURL, apiKey: "", model: preferences.model).host ?? "configured endpoint"
    }

    init(
        preferences: Preferences,
        keychain: APIKeyStoring,
        captureService: ScreenCaptureService,
        apiClient: OpenAICompatibleClient
    ) {
        self.preferences = preferences
        self.keychain = keychain
        self.captureService = captureService
        self.apiClient = apiClient
    }

    func reset() {
        currentCaptureTask?.cancel()
        currentGenerationTask?.cancel()
        currentCaptureTask = nil
        currentGenerationTask = nil
        prompt = ""
        messages = []
        screenContextState = .disabled
        generationState = .idle
        isPreviewPresented = false
        firstScreenData = nil
    }

    func dismiss() {
        reset()
    }

    func beginCapture(for screen: NSScreen) {
        currentCaptureTask?.cancel()

        guard CGPreflightScreenCaptureAccess() else {
            screenContextState = .permissionRequired
            return
        }

        screenContextState = .capturing
        let displayID = DisplayResolver.displayID(for: screen)
        currentCaptureTask = Task { [weak self, captureService] in
            do {
                let data = try await captureService.capture(displayID: displayID)
                try Task.checkCancellation()
                guard let self else { return }
                self.screenContextState = .ready(data)
            } catch is CancellationError {
                return
            } catch let error as KKError {
                guard let self else { return }
                if case .screenCapturePermission = error {
                    self.screenContextState = .permissionRequired
                } else {
                    self.screenContextState = .failed(error.localizedDescription)
                }
            } catch {
                guard let self else { return }
                self.screenContextState = .failed(error.localizedDescription)
            }
        }
    }

    func removeScreen() {
        currentCaptureTask?.cancel()
        currentCaptureTask = nil
        isPreviewPresented = false
        guard !hasSubmitted else { return }
        screenContextState = .disabled
    }

    func requestScreenAccess() {
        captureService.requestAccess()
    }

    func openSystemSettings() {
        captureService.openSystemSettings()
    }

    func togglePreview() {
        guard currentPreviewData != nil else { return }
        isPreviewPresented.toggle()
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

        if case .ready(let data) = screenContextState {
            firstScreenData = data
            screenContextState = .sent(data)
        }

        prompt = ""
        messages.append(ChatMessage(role: .user, content: text))
        let assistantID = UUID()
        messages.append(ChatMessage(id: assistantID, role: .assistant, content: ""))
        generationState = .streaming

        let requestMessages = makeAPIMessages(firstImage: firstScreenData)
        let request = ChatCompletionRequest(model: configuration.model, messages: requestMessages, stream: true)

        currentGenerationTask?.cancel()
        currentGenerationTask = Task { [weak self, apiClient] in
            do {
                for try await delta in apiClient.streamCompletion(request: request, configuration: configuration) {
                    try Task.checkCancellation()
                    guard let self else { return }
                    if let index = self.messages.firstIndex(where: { $0.id == assistantID }) {
                        self.messages[index].content.append(delta)
                    }
                }
                guard let self else { return }
                self.generationState = .completed
                self.currentGenerationTask = nil
            } catch is CancellationError {
                guard let self else { return }
                self.generationState = .completed
                self.currentGenerationTask = nil
            } catch let error as KKError {
                guard let self else { return }
                self.generationState = .error(error)
                self.currentGenerationTask = nil
            } catch let error as URLError {
                guard let self else { return }
                self.generationState = .error(.network(error.localizedDescription))
                self.currentGenerationTask = nil
            } catch {
                guard let self else { return }
                self.generationState = .error(.streamFailed(error.localizedDescription))
                self.currentGenerationTask = nil
            }
        }
    }

    func stop() {
        guard isStreaming else { return }
        currentGenerationTask?.cancel()
        currentGenerationTask = nil
        generationState = .completed
    }

    func retry() {
        guard let lastUser = messages.last(where: { $0.role == .user }) else { return }
        if let lastIndex = messages.lastIndex(where: { $0.role == .assistant }) {
            messages.remove(at: lastIndex)
        }
        prompt = lastUser.content
        if messages.last?.role == .user { messages.removeLast() }
        submit()
    }

    func copyLastAnswer() {
        guard let answer = messages.last(where: { $0.role == .assistant }), !answer.content.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(answer.content, forType: .string)
    }

    private func makeAPIMessages(firstImage: Data?) -> [APIMessage] {
        var result = [APIMessage(role: "system", content: .text(KKCopy.systemPrompt))]
        var image = firstImage

        for message in messages {
            if message.role == .user, let imageData = image {
                let base64 = imageData.base64EncodedString()
                result.append(APIMessage(role: "user", content: .parts([
                    .text(message.content),
                    .imageURL("data:image/jpeg;base64,\(base64)")
                ])))
                image = nil
            } else {
                result.append(APIMessage(role: message.role.rawValue, content: .text(message.content)))
            }
        }
        return result
    }
}
