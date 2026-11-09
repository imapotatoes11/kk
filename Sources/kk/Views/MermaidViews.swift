import AppKit
import MarkdownView
import SwiftUI
import WebKit

/// Renders ```mermaid fences as diagrams and every other code block with MarkdownView's default.
struct KKCodeBlockStyle: MarkdownCodeBlockStyle {
    func makeBody(configuration: Configuration) -> some View {
        KKCodeBlock(configuration: configuration)
    }
}

private struct KKCodeBlock: View {
    let configuration: MarkdownCodeBlockStyleConfiguration
    @Environment(\.kkRenderDiagrams) private var renderDiagrams
    @Environment(\.kkMermaidRepairs) private var repairs

    var body: some View {
        if renderDiagrams, configuration.language?.lowercased() == "mermaid" {
            MermaidBlockView(configuration: configuration, store: repairs ?? .empty)
        } else {
            DefaultCodeBlockStyle().makeBody(configuration: configuration)
        }
    }
}

struct MermaidBlockView: View {
    let configuration: MarkdownCodeBlockStyleConfiguration
    @ObservedObject var store: MermaidRepairStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.kkMarkdownStreaming) private var isStreaming
    @Environment(\.kkDiagramAccent) private var accent
    @Environment(\.kkDiagramTextSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rendered: Rendered?
    @State private var showSource = false
    @State private var expanded = false
    @State private var hovering = false
    @State private var availableWidth: CGFloat = 480
    @State private var handle = MermaidWebViewHandle()
    /// A clipped diagram shows a persistent scroll hint until the user scrolls it sideways.
    @State private var scrolledSideways = false

    /// Mermaid draws labels at this size (see `MermaidTheme`).
    static let diagramFontSize: CGFloat = 13
    /// Labels read like captions: a little smaller than the chat text.
    static let labelRatio: CGFloat = 0.9
    /// Wide diagrams shrink to fit, but labels never drop below this; they scroll instead.
    static let minimumLabelSize: CGFloat = 10

    struct Layout: Equatable {
        let size: CGSize
        let scrolls: Bool
    }

    /// Scales a diagram so its labels match the chat text size, shrinking to fit the available
    /// width down to a readable minimum. Diagrams wider than that scroll horizontally.
    static func layout(natural: CGSize, available: CGFloat, textSize: CGFloat) -> Layout {
        guard natural.width > 0, natural.height > 0 else { return Layout(size: .zero, scrolls: false) }
        let preferred = textSize * labelRatio / diagramFontSize
        let minimum = minimumLabelSize / diagramFontSize
        let fitting = available / natural.width
        let scale = max(min(preferred, fitting), min(minimum, preferred))
        let size = CGSize(width: floor(natural.width * scale), height: floor(natural.height * scale))
        return Layout(size: size, scrolls: size.width > available + 0.5)
    }

    private struct Rendered: Equatable {
        let key: String
        let result: MermaidRenderResult
    }

    private struct RenderRequest: Equatable {
        let key: String
        let theme: MermaidTheme
        let enabled: Bool
    }

    private var key: String { MermaidExtractor.key(configuration.code) }
    private var theme: MermaidTheme { MermaidTheme(isDark: colorScheme == .dark, accent: accent) }
    private var status: MermaidRepairStore.Status? { store.status(for: configuration.code) }
    private var canRender: Bool { !isStreaming && status == nil }
    private var result: MermaidRenderResult? { rendered?.key == key ? rendered?.result : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
            if showSource, case .diagram = result {
                DefaultCodeBlockStyle().makeBody(configuration: configuration)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: RenderRequest(key: key, theme: theme, enabled: canRender)) {
            guard canRender else { return }
            let requested = key
            let output = await MermaidRenderer.shared.render(configuration.code, theme: theme)
            guard !Task.isCancelled else { return }
            rendered = Rendered(key: requested, result: output)
        }
    }

    @ViewBuilder private var content: some View {
        if isStreaming || status == .checking {
            progressCard("Drawing diagram…")
        } else if status == .repairing {
            progressCard("Fixing diagram…")
        } else if case .failed(let message) = status {
            failure(message)
        } else {
            switch result {
            case .diagram(let svg, let size): diagram(svg: svg, size: size)
            case .failure(let message): failure(message)
            case nil: progressCard("Drawing diagram…")
            }
        }
    }

    private func diagram(svg: String, size: CGSize) -> some View {
        let layout = Self.layout(natural: size, available: max(80, availableWidth - 24), textSize: textSize)
        return card {
            if layout.scrolls {
                ScrollView(.horizontal) {
                    MermaidWebView(svg: svg, handle: handle)
                        .frame(width: layout.size.width, height: layout.size.height)
                }
                .scrollIndicators(.automatic)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, offset in
                    if abs(offset) > 1 && !scrolledSideways { scrolledSideways = true }
                }
                .frame(height: layout.size.height + 12)
                .overlay(alignment: .bottom) {
                    if showsScrollHint {
                        ScrollHint(contentWidth: layout.size.width).transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: scrolledSideways)
            } else {
                // Flexible rather than fixed, so a narrower window shrinks the diagram instead of
                // the diagram holding the window's content wide (its width is measured from here).
                MermaidWebView(svg: svg, handle: handle)
                    .aspectRatio(size.width / size.height, contentMode: .fit)
                    .frame(maxWidth: layout.size.width)
                    .frame(maxWidth: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hovering { toolbar(svg: svg, size: size).padding(6).transition(.opacity) }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
        .onHover { hovering = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { expanded = true }
        .popover(isPresented: $expanded, arrowEdge: .top) {
            MermaidExpandedView(svg: svg, size: size, source: configuration.code)
        }
        .contextMenu {
            Button("Copy Image") { copyImage() }
            Button("Copy Mermaid Source") { copySource() }
            Button(showSource ? "Hide Source" : "Show Source") { showSource.toggle() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Diagram")
        .accessibilityHint("Click to enlarge")
        .accessibilityAction(named: "Copy Mermaid source") { copySource() }
    }

    /// Overlay scroll bars stay hidden until scrolling, so a clipped diagram could look complete.
    /// With "Always show scroll bars", the system bar is already visible and no hint is needed.
    private var showsScrollHint: Bool {
        !scrolledSideways && NSScroller.preferredScrollerStyle == .overlay
    }

    private func toolbar(svg: String, size: CGSize) -> some View {
        HStack(spacing: 2) {
            toolbarButton("arrow.up.left.and.arrow.down.right", "Enlarge diagram") { expanded = true }
            toolbarButton("doc.on.doc", "Copy diagram image") { copyImage() }
            toolbarButton("chevron.left.forwardslash.chevron.right", showSource ? "Hide Mermaid source" : "Show Mermaid source") { showSource.toggle() }
        }
        .padding(3)
        .background(.regularMaterial, in: Capsule())
        .overlay { Capsule().strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5) }
    }

    private func toolbarButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .medium)).frame(width: 24, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(label)
        .accessibilityLabel(label)
    }

    private func progressCard(_ text: String) -> some View {
        card {
            HStack(spacing: 8) {
                ThinkingGlyph().frame(width: 20, height: 16)
                Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .accessibilityElement(children: .combine)
    }

    private func failure(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Couldn't draw this diagram", systemImage: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .help(message)
                .accessibilityHint(message)
            DefaultCodeBlockStyle().makeBody(configuration: configuration)
        }
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5).allowsHitTesting(false) }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                if abs(width - availableWidth) > 0.5 { availableWidth = width }
            }
    }

    private func copyImage() {
        guard let webView = handle.webView else { return }
        Task { @MainActor in
            guard let image = try? await webView.takeSnapshot(configuration: nil) else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }
    }

    private func copySource() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("```mermaid\n\(key)\n```", forType: .string)
    }

    /// Scales down to fit, keeping the aspect ratio. Small diagrams keep their natural size.
    static func fit(_ size: CGSize, width: CGFloat, height: CGFloat) -> CGSize {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(1, width / size.width, height / size.height)
        return CGSize(width: floor(size.width * scale), height: floor(size.height * scale))
    }
}

/// A static scroll bar showing that a diagram continues to the right. It matches the overlay
/// scroller's look and position at the start of the content.
private struct ScrollHint: View {
    let contentWidth: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let track = geometry.size.width - 4
            let thumb = max(24, track * min(1, geometry.size.width / max(contentWidth, 1)))
            Capsule()
                .fill(Color.primary.opacity(0.35))
                .frame(width: thumb, height: 6)
                .offset(x: 2, y: (geometry.size.height - 6) / 2)
        }
        .frame(height: 10)
        .padding(.bottom, 1)
        .allowsHitTesting(false)
        .accessibilityLabel("Scroll sideways to see the whole diagram")
    }
}

/// A larger view of a diagram, opened by clicking it.
private struct MermaidExpandedView: View {
    let svg: String
    let size: CGSize
    let source: String
    @State private var handle = MermaidWebViewHandle()

    var body: some View {
        let screen = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1200, height: 800)
        // Enlarge small diagrams up to 1.75×, and fit large ones within the screen.
        let target = CGSize(width: min(size.width * 1.75, screen.width * 0.7), height: min(size.height * 1.75, screen.height * 0.7))
        let fitted = MermaidBlockView.fit(size, width: target.width, height: target.height)
        let scale = max(1, min(target.width / size.width, target.height / size.height))
        let display = size.width * scale <= target.width + 1 && size.height * scale <= target.height + 1
            ? CGSize(width: floor(size.width * scale), height: floor(size.height * scale)) : fitted
        VStack(alignment: .trailing, spacing: 10) {
            MermaidWebView(svg: svg, handle: handle)
                .frame(width: display.width, height: display.height)
                .padding(16)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 12) {
                Button("Copy Mermaid Source") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("```mermaid\n\(MermaidExtractor.key(source))\n```", forType: .string)
                }
                Button("Copy Image") {
                    guard let webView = handle.webView else { return }
                    Task { @MainActor in
                        guard let image = try? await webView.takeSnapshot(configuration: nil) else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([image])
                    }
                }
            }
            .controlSize(.small)
        }
        .padding(14)
    }
}

@MainActor
final class MermaidWebViewHandle {
    weak var webView: WKWebView?
}

/// Displays a rendered SVG. Scripts are disabled, nothing can navigate, and the view never
/// takes mouse events, so scrolling and clicks reach the conversation around it.
struct MermaidWebView: NSViewRepresentable {
    let svg: String
    var handle: MermaidWebViewHandle?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PassiveWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = PassiveWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        view.setAccessibilityElement(false)
        handle?.webView = view
        load(into: view, context: context)
        return view
    }

    func updateNSView(_ view: PassiveWebView, context: Context) {
        handle?.webView = view
        if context.coordinator.loadedSVG != svg { load(into: view, context: context) }
    }

    private func load(into view: WKWebView, context: Context) {
        context.coordinator.loadedSVG = svg
        view.loadHTMLString(Self.document(svg), baseURL: nil)
    }

    static func document(_ svg: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:">
        <style>html,body{margin:0;padding:0;background:transparent;overflow:hidden}
        svg{display:block;width:100%!important;height:auto!important;max-width:none!important}</style>
        </head><body>\(svg)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedSVG: String?

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            navigationAction.request.url?.scheme == "about" ? .allow : .cancel
        }
    }
}

final class PassiveWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func scrollWheel(with event: NSEvent) { nextResponder?.scrollWheel(with: event) }
}
