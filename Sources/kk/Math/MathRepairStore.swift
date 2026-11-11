import SwiftUI

/// Tracks equations being fixed after an answer finishes, so their views show progress and,
/// if the fix fails, why.
@MainActor
final class MathRepairStore: ObservableObject {
    enum Status: Equatable {
        case repairing
        case failed(String)
    }

    @Published private(set) var statuses: [String: Status] = [:]

    static let empty = MathRepairStore()

    func status(for source: String) -> Status? {
        statuses[MathMarkdown.key(source)]
    }

    func set(_ source: String, _ status: Status?) {
        let key = MathMarkdown.key(source)
        guard statuses[key] != status else { return }
        statuses[key] = status
    }

    func reset() {
        if !statuses.isEmpty { statuses = [:] }
    }
}

extension EnvironmentValues {
    @Entry var kkMathRepairs: MathRepairStore? = nil
    /// Asks the model to fix an equation that can't render, identified by its source.
    @Entry var kkRepairEquation: (@MainActor (String) -> Void)? = nil
}
