import Foundation

struct ChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: Role
    var content: String
    var screenData: Data?
    var additionalScreenData: [Data] = []
    var screenNames: [String] = []
    var reasoning = ""
    var generationStartedAt: Date?
    var reasoningStartedAt: Date?
    var reasoningEndedAt: Date?

    func thinkingDuration(at now: Date = .now) -> TimeInterval {
        guard let reasoningStartedAt else { return 0 }
        return max(0, (reasoningEndedAt ?? now).timeIntervalSince(reasoningStartedAt))
    }

    init(id: UUID = UUID(), role: Role, content: String, screenData: Data? = nil, additionalScreenData: [Data] = [], screenNames: [String] = []) {
        self.id = id
        self.role = role
        self.content = content
        self.screenData = screenData
        self.additionalScreenData = additionalScreenData
        self.screenNames = screenNames
    }
}

enum Role: String, Sendable {
    case user
    case assistant
}
