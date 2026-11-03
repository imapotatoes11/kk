import Foundation

struct ChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: Role
    var content: String
    var reasoning = ""
    var generationStartedAt: Date?
    var reasoningStartedAt: Date?
    var reasoningEndedAt: Date?

    func thinkingDuration(at now: Date = .now) -> TimeInterval {
        guard let reasoningStartedAt else { return 0 }
        return max(0, (reasoningEndedAt ?? now).timeIntervalSince(reasoningStartedAt))
    }

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }
}

enum Role: String, Sendable {
    case user
    case assistant
}
