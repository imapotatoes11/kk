import AppKit
import SwiftUI

/// Tracks diagrams that are being checked or fixed after an answer finishes, so their views can
/// show progress instead of flashing an error before the repair lands.
@MainActor
final class MermaidRepairStore: ObservableObject {
    enum Status: Equatable {
        case checking
        case repairing
        case failed(String)
    }

    @Published private(set) var statuses: [String: Status] = [:]

    static let empty = MermaidRepairStore()

    func status(for code: String) -> Status? {
        statuses[MermaidExtractor.key(code)]
    }

    func set(_ code: String, _ status: Status?) {
        let key = MermaidExtractor.key(code)
        guard statuses[key] != status else { return }
        statuses[key] = status
    }

    func reset() {
        if !statuses.isEmpty { statuses = [:] }
    }
}

extension EnvironmentValues {
    @Entry var kkMarkdownStreaming = false
    @Entry var kkRenderDiagrams = true
    @Entry var kkDiagramAccent: NSColor? = nil
    /// The chat text size, so diagram labels can be scaled to match it.
    @Entry var kkDiagramTextSize: CGFloat = 14
    @Entry var kkMermaidRepairs: MermaidRepairStore? = nil
}
