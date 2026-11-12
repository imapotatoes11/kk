import Foundation

struct APIConfiguration: Sendable {
    let baseURL: String
    let apiKey: String
    let model: String

    var customParameters = "{}"
    var reasoningEffort: String? = nil
    var retryWithoutReasoning = false
    var reasoningPolicy: (@Sendable () async -> ReasoningPolicy)? = nil
    var onReasoningFailure: (@Sendable () async -> Void)? = nil

    struct ReasoningPolicy: Sendable {
        let effort: String?
        let trial: Bool
    }

    var endpointURL: URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme) else { return nil }

        let normalized = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        let endpoint = normalized.hasSuffix("/chat/completions")
            ? normalized
            : normalized + "/chat/completions"
        return URL(string: endpoint)
    }

    var host: String? { endpointURL?.host }

    func validated() throws -> APIConfiguration {
        guard endpointURL != nil else { throw KKError.invalidBaseURL }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw KKError.invalidModel }
        return self
    }
}
