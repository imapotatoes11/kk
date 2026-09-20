import MarkdownView
import SwiftUI

struct ResponseView: View {
    let markdown: String
    let isStreaming: Bool
    @State private var markdownSource = StreamingMarkdownSource()

    var body: some View {
        StreamingMarkdownReader(markdownSource) { parseResult in
            MarkdownView(parseResult)
                .font(.system(size: 14), for: .body)
                .markdownElementRenderer(.image(ExternalImagePlaceholderRenderer(), urlScheme: "http"))
                .markdownElementRenderer(.image(ExternalImagePlaceholderRenderer(), urlScheme: "https"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .markdownMathRenderingEnabled()
        .accessibilityLabel(isStreaming ? "Answer streaming" : "Assistant answer")
        .onAppear {
            markdownSource.text = markdown
            if !isStreaming { markdownSource.finishStreaming() }
        }
        .onChange(of: markdown) { _, value in
            markdownSource.text = value
        }
        .onChange(of: isStreaming) { _, streaming in
            if !streaming { markdownSource.finishStreaming() }
        }
    }
}

private struct ExternalImagePlaceholderRenderer: MarkdownImageRenderer {
    func makeBody(configuration: Configuration) -> some View {
        Label("External image not loaded", systemImage: "photo.on.rectangle")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .accessibilityLabel("External image omitted")
    }
}
