import Foundation

struct ChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: Role
    var content: String
    var screenData: Data?
    var additionalScreenData: [Data] = []
    var screenNames: [String] = []
    var attachments: [Attachment] = []
    var isComplete = true
    var isInferred = false
    var previousVersions: [MessageVersion] = []
    var reasoning = ""
    var generationStartedAt: Date?
    var reasoningStartedAt: Date?
    var reasoningEndedAt: Date?

    var version: MessageVersion {
        MessageVersion(content: content, reasoning: reasoning, generationStartedAt: generationStartedAt,
            reasoningStartedAt: reasoningStartedAt, reasoningEndedAt: reasoningEndedAt, isInferred: isInferred)
    }

    func displayingVersion(_ index: Int?) -> ChatMessage {
        guard let index, previousVersions.indices.contains(index) else { return self }
        var message = self
        message.apply(previousVersions[index])
        return message
    }

    mutating func replace(with replacement: ChatMessage) {
        if version != replacement.version { previousVersions.append(version) }
        apply(replacement.version)
        isComplete = replacement.isComplete
    }

    private mutating func apply(_ version: MessageVersion) {
        content = version.content
        reasoning = version.reasoning
        generationStartedAt = version.generationStartedAt
        reasoningStartedAt = version.reasoningStartedAt
        reasoningEndedAt = version.reasoningEndedAt
        isInferred = version.isInferred
    }

    func thinkingDuration(at now: Date = .now) -> TimeInterval {
        guard let reasoningStartedAt else { return 0 }
        return max(0, (reasoningEndedAt ?? now).timeIntervalSince(reasoningStartedAt))
    }

    init(id: UUID = UUID(), role: Role, content: String, screenData: Data? = nil, additionalScreenData: [Data] = [], screenNames: [String] = [], attachments: [Attachment] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.screenData = screenData
        self.additionalScreenData = additionalScreenData
        self.screenNames = screenNames
        self.attachments = attachments
    }
}

enum Role: String, Sendable {
    case user
    case assistant
}
