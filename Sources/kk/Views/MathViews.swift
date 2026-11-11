import MarkdownView
import SwiftUI

/// Display math that still can't render after compatibility fixes: its source, with progress
/// while the model fixes it, or a notice and a Fix button once the answer has finished.
struct MathFailureView: View {
    let configuration: MarkdownCodeBlockStyleConfiguration
    @ObservedObject var store: MathRepairStore
    @Environment(\.kkMarkdownStreaming) private var isStreaming
    @Environment(\.kkRepairEquation) private var repair

    private var status: MathRepairStore.Status? { store.status(for: configuration.code) }

    private var source: MarkdownCodeBlockStyleConfiguration {
        var source = configuration
        source.language = "latex"
        return source
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if status == .repairing {
                HStack(spacing: 8) {
                    ThinkingGlyph().frame(width: 20, height: 16)
                    Text("Fixing equation…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } else if !isStreaming {
                notice
            }
            DefaultCodeBlockStyle().makeBody(configuration: source)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notice: some View {
        HStack(spacing: 10) {
            Label("Couldn't render this equation", systemImage: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .help(failureMessage)
                .accessibilityHint(failureMessage)
            if let repair {
                Button(status == nil ? "Fix" : "Try Again") { repair(configuration.code) }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .help("Ask your model to correct this equation")
            }
        }
    }

    private var failureMessage: String {
        if case .failed(let message) = status { return message }
        return LaTeXCompatibility.error(in: configuration.code) ?? "This equation uses LaTeX that kk can't draw."
    }
}
