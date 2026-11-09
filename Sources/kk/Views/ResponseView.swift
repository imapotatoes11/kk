import MarkdownView
import SwiftUI

struct ResponseView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.kkWrapLaTeX) private var wrapLaTeX
    @State private var availableWidth: CGFloat = 0
    let markdown: String
    let isStreaming: Bool
    var textSize: CGFloat = 14

    private var renderedMarkdown: String {
        wrapLaTeX ? LaTeXWrapping.markdown(markdown, width: availableWidth, fontSize: textSize + 2) : markdown
    }

    var body: some View {
        Group {
            if isStreaming {
                StreamingResponse(markdown: renderedMarkdown)
            } else {
                // A completed answer must not depend on an already-finished update stream.
                // This also gives reference links, tables and math a final full parse.
                MarkdownReader(renderedMarkdown) { result in
                    MarkdownView(result)
                        .foregroundColor(colorScheme == .dark ? .white : .primary)
                }
            }
        }
        .markdownFontGroup(AnswerFonts(size: textSize))
        .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
        .foregroundColor(colorScheme == .dark ? .white : .primary)
        .markdownMathRenderingEnabled()
        .markdownCodeBlockStyle(KKCodeBlockStyle())
        .environment(\.kkMarkdownStreaming, isStreaming)
        .environment(\.kkDiagramTextSize, textSize)
        .markdownElementRenderer(.image(ExternalImagePlaceholderRenderer(), urlScheme: "http"))
        .markdownElementRenderer(.image(ExternalImagePlaceholderRenderer(), urlScheme: "https"))
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            if abs(width - availableWidth) > 1 { availableWidth = width }
        }
        .accessibilityLabel(isStreaming ? "Answer streaming" : "Assistant answer")
    }
}

private struct AnswerFonts: MarkdownFontGroup {
    let size: CGFloat
    var h1: any CustomCTFontConvertible { heading(.largeTitle) }
    var h2: any CustomCTFontConvertible { heading(.title1) }
    var h3: any CustomCTFontConvertible { heading(.title2) }
    var h4: any CustomCTFontConvertible { heading(.title3) }
    var h5: any CustomCTFontConvertible { heading(.headline) }
    var h6: any CustomCTFontConvertible {
        NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: .headline).pointSize * size / 14)
    }
    var body: any CustomCTFontConvertible { NSFont.systemFont(ofSize: size) }
    var blockQuote: any CustomCTFontConvertible { NSFont.systemFont(ofSize: size) }
    var tableBody: any CustomCTFontConvertible { NSFont.systemFont(ofSize: size) }
    var tableHeader: any CustomCTFontConvertible { NSFont.systemFont(ofSize: size, weight: .semibold) }
    var codeBlock: any CustomCTFontConvertible { NSFont.monospacedSystemFont(ofSize: size - 1, weight: .regular) }
    var inlineMath: any CustomCTFontConvertible { NSFont.systemFont(ofSize: size) }
    var displayMath: any CustomCTFontConvertible { NSFont.systemFont(ofSize: size + 2) }

    private func heading(_ style: NSFont.TextStyle) -> NSFont {
        let font = NSFont.preferredFont(forTextStyle: style)
        return NSFont(descriptor: font.fontDescriptor, size: font.pointSize * size / 14) ?? font
    }
}

private struct StreamingResponse: View {
    @Environment(\.colorScheme) private var colorScheme
    let markdown: String
    @State private var source: StreamingMarkdownSource

    init(markdown: String) {
        self.markdown = markdown
        _source = State(initialValue: StreamingMarkdownSource(markdown))
    }

    var body: some View {
        StreamingMarkdownReader(source) { parseResult in
            MarkdownView(parseResult)
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
                .foregroundColor(colorScheme == .dark ? .white : .primary)
        }
        .onChange(of: markdown) { _, value in
            source.text = value
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
