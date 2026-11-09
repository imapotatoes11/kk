import AppKit
import SwiftUI
import WebKit

enum MermaidRenderResult: Equatable, Sendable {
    case diagram(svg: String, size: CGSize)
    case failure(String)
}

/// Mermaid styling that matches kk: system font, the chosen accent for nodes, quiet gray lines,
/// rounded shapes, and thin strokes, with light and dark variants.
struct MermaidTheme: Hashable, Sendable {
    var isDark: Bool
    /// The accent as `#RRGGBB` in sRGB.
    var accent: String

    init(isDark: Bool, accent: NSColor?) {
        self.isDark = isDark
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        var hex = isDark ? "#0A84FF" : "#007AFF"
        appearance?.performAsCurrentDrawingAppearance {
            if let color = (accent ?? .controlAccentColor).usingColorSpace(.sRGB) { hex = Self.hex(color) }
        }
        self.accent = hex
    }

    /// Matches the diagram card, so edge labels blend into it.
    var background: String { isDark ? "#1E1E1E" : "#FFFFFF" }
    private var text: String { isDark ? "#F5F5F7" : "#1D1D1F" }
    private var secondaryText: String { isDark ? "#C7C7CC" : "#6E6E73" }
    private var line: String { isDark ? "#8E8E93" : "#8E8E93" }
    private var nodeFill: String { Self.mix(accent, background, isDark ? 0.24 : 0.10) }
    private var nodeBorder: String { Self.mix(accent, background, isDark ? 0.70 : 0.55) }
    private var subtleFill: String { isDark ? "#2C2C2E" : "#F5F5F7" }
    private var subtleBorder: String { isDark ? "#3A3A3C" : "#D1D1D6" }

    static let fontFamily = "-apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Helvetica Neue', sans-serif"

    var variables: [String: Any] {
        [
            "darkMode": isDark,
            "background": background,
            "fontFamily": Self.fontFamily,
            "fontSize": "13px",
            "primaryColor": nodeFill,
            "primaryBorderColor": nodeBorder,
            "primaryTextColor": text,
            "secondaryColor": subtleFill,
            "secondaryBorderColor": subtleBorder,
            "secondaryTextColor": text,
            "tertiaryColor": background,
            "tertiaryBorderColor": subtleBorder,
            "tertiaryTextColor": text,
            "mainBkg": nodeFill,
            "nodeBorder": nodeBorder,
            "nodeTextColor": text,
            "textColor": text,
            "titleColor": text,
            "lineColor": line,
            "defaultLinkColor": line,
            "edgeLabelBackground": background,
            "clusterBkg": subtleFill,
            "clusterBorder": subtleBorder,
            "noteBkgColor": isDark ? "#3A3422" : "#FFF7D9",
            "noteBorderColor": isDark ? "#6E5F2D" : "#E8D48B",
            "noteTextColor": text,
            "actorBkg": nodeFill,
            "actorBorder": nodeBorder,
            "actorTextColor": text,
            "actorLineColor": subtleBorder,
            "signalColor": line,
            "signalTextColor": text,
            "labelBoxBkgColor": nodeFill,
            "labelBoxBorderColor": nodeBorder,
            "labelTextColor": text,
            "loopTextColor": secondaryText,
            "activationBkgColor": subtleFill,
            "activationBorderColor": nodeBorder,
            "sequenceNumberColor": isDark ? "#1E1E1E" : "#FFFFFF",
            "labelColor": text,
            "altBackground": subtleFill,
            "attributeBackgroundColorOdd": background,
            "attributeBackgroundColorEven": subtleFill,
            "pieStrokeColor": background,
            "pieOuterStrokeColor": subtleBorder,
            "pieTitleTextColor": text,
            "pieSectionTextColor": text,
            "pieLegendTextColor": text,
            "git0": accent
        ]
    }

    var css: String {
        """
        .node rect, .node polygon, .node circle, .node ellipse, .node path { stroke-width: 1.25px; }
        .node rect, .basic.label-container, rect.actor, rect.note, rect.labelBox, .stateGroup rect { rx: 8px; ry: 8px; }
        .cluster rect { rx: 10px; ry: 10px; stroke-width: 1px; }
        .flowchart-link, .edgePath .path, .messageLine0, .messageLine1, .relation, .transition { stroke-width: 1.25px; }
        .nodeLabel, .label foreignObject div, .actor tspan, .messageText, .stateLabel text { font-weight: 500; }
        .edgeLabel, .edgeLabel p, .edgeLabel span { font-size: 12px; color: \(secondaryText); background-color: \(background); }
        .edgeLabel rect { fill: \(background); opacity: 1; }
        .loopText, .loopText tspan, .labelText { font-size: 12px; }
        .cluster-label .nodeLabel { font-weight: 600; color: \(secondaryText); }
        """
    }

    var configuration: [String: Any] {
        [
            "startOnLoad": false,
            "securityLevel": "strict",
            "theme": "base",
            "deterministicIds": true,
            "fontFamily": Self.fontFamily,
            "themeVariables": variables,
            "themeCSS": css,
            "flowchart": ["htmlLabels": true, "curve": "basis", "padding": 12, "nodeSpacing": 36, "rankSpacing": 44, "diagramPadding": 8],
            "sequence": [
                "mirrorActors": false, "actorMargin": 36, "boxMargin": 8, "noteMargin": 8, "messageMargin": 30,
                "width": 120, "height": 50, "diagramMarginX": 8, "diagramMarginY": 8,
                "actorFontSize": 13, "messageFontSize": 13, "noteFontSize": 12,
                "actorFontFamily": Self.fontFamily, "messageFontFamily": Self.fontFamily, "noteFontFamily": Self.fontFamily
            ],
            "state": ["padding": 10]
        ]
    }

    static func hex(_ color: NSColor) -> String {
        let r = Int((color.redComponent * 255).rounded()), g = Int((color.greenComponent * 255).rounded()), b = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }

    /// `amount` of `foreground` over `background`, as an opaque color.
    static func mix(_ foreground: String, _ background: String, _ amount: Double) -> String {
        func components(_ hex: String) -> [Double] {
            let value = Int(hex.dropFirst(), radix: 16) ?? 0
            return [Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF)]
        }
        let mixed = zip(components(foreground), components(background)).map { Int(($0 * amount + $1 * (1 - amount)).rounded()) }
        return String(format: "#%02X%02X%02X", mixed[0], mixed[1], mixed[2])
    }
}

/// Validates and renders Mermaid diagrams with the bundled Mermaid library in a hidden web view.
/// The page has no network access, scripts run only from the bundle, and navigation is blocked.
@MainActor
final class MermaidRenderer: NSObject, WKNavigationDelegate {
    static let shared = MermaidRenderer()
    static let version = "11.17.2"

    private var webView: WKWebView?
    private var loading: Task<Bool, Never>?
    private var loadContinuation: CheckedContinuation<Bool, Never>?
    private var tail: Task<Void, Never>?
    private var renderCache: [String: MermaidRenderResult] = [:]
    private var validationCache: [String: String?] = [:]
    private var counter = 0

    static var scriptURL: URL? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "Mermaid") { return url }
        #endif
        return Bundle.main.url(forResource: "mermaid.min", withExtension: "js")
            ?? Bundle.main.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "Mermaid")
    }

    /// Returns the parser's error message, or nil when the diagram is valid.
    func validate(_ code: String) async -> String? {
        let key = MermaidExtractor.key(code)
        if let cached = validationCache[key] { return cached }
        let error: String? = await serialized { [self] in
            guard await self.prepare(), let webView = self.webView else { return "Diagram rendering isn't available." }
            do {
                let value = try await webView.callAsyncJavaScript("return await window.kkMermaid.parse(code)", arguments: ["code": key], in: nil, contentWorld: .page)
                return value as? String
            } catch {
                return error.localizedDescription
            }
        }
        validationCache[key] = error
        return error
    }

    func render(_ code: String, theme: MermaidTheme) async -> MermaidRenderResult {
        let key = MermaidExtractor.key(code)
        let cacheKey = "\(theme.isDark)|\(theme.accent)|\(key)"
        if let cached = renderCache[cacheKey] { return cached }
        let result: MermaidRenderResult = await serialized { [self] in
            guard await self.prepare(), let webView = self.webView else { return .failure("Diagram rendering isn't available.") }
            self.counter += 1
            do {
                let value = try await webView.callAsyncJavaScript(
                    "return await window.kkMermaid.render(code, config, id)",
                    arguments: ["code": key, "config": theme.configuration, "id": "kk-diagram-\(self.counter)"],
                    in: nil, contentWorld: .page
                )
                guard let object = value as? [String: Any] else { return .failure("The diagram couldn't be drawn.") }
                if let error = object["error"] as? String { return .failure(error) }
                guard let svg = object["svg"] as? String,
                      let width = (object["width"] as? NSNumber)?.doubleValue, let height = (object["height"] as? NSNumber)?.doubleValue,
                      width > 0, height > 0 else { return .failure("The diagram is empty.") }
                return .diagram(svg: svg, size: CGSize(width: width, height: height))
            } catch {
                return .failure(error.localizedDescription)
            }
        }
        renderCache[cacheKey] = result
        if case .failure(let message) = result { validationCache[key] = message }
        return result
    }

    // MARK: - Page setup

    /// Mermaid keeps global configuration, so calls run one at a time.
    private func serialized<T: Sendable>(_ work: @escaping @MainActor () async -> T) async -> T {
        let previous = tail
        let task = Task { @MainActor in
            _ = await previous?.value
            return await work()
        }
        tail = Task { _ = await task.value }
        return await task.value
    }

    private func prepare() async -> Bool {
        if let loading { return await loading.value }
        let task = Task { @MainActor in await self.load() }
        loading = task
        let ready = await task.value
        if !ready { loading = nil; webView = nil }
        return ready
    }

    private func load() async -> Bool {
        guard let url = Self.scriptURL, let library = try? String(contentsOf: url, encoding: .utf8) else { return false }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(source: library + "\n" + Self.bridge, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1600, height: 1200), configuration: configuration)
        view.navigationDelegate = self
        webView = view
        return await withCheckedContinuation { continuation in
            loadContinuation = continuation
            view.loadHTMLString(Self.page, baseURL: nil)
        }
    }

    private func finishLoading(_ success: Bool) {
        loadContinuation?.resume(returning: success)
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoading(true) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishLoading(false) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finishLoading(false) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Reload lazily on the next request.
        self.webView = nil
        loading = nil
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        // Only the initial blank page may load. Links in diagrams never navigate.
        loadContinuation != nil && navigationAction.request.url?.scheme == "about" ? .allow : .cancel
    }

    private static let page = """
    <!doctype html><html><head><meta charset="utf-8">
    <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:">
    </head><body><div id="holder" style="position:absolute;left:-10000px;top:0"></div></body></html>
    """

    private static let bridge = """
    mermaid.initialize({ startOnLoad: false, securityLevel: 'strict' });
    window.kkMermaid = {
      async parse(code) {
        try { await mermaid.parse(code); return null; }
        catch (e) { return String((e && (e.message || e.str)) || e); }
      },
      async render(code, config, id) {
        mermaid.initialize(config);
        try {
          const { svg } = await mermaid.render(id, code);
          const holder = document.getElementById('holder');
          holder.innerHTML = svg;
          const el = holder.querySelector('svg');
          let width = 0, height = 0;
          const box = el && el.viewBox && el.viewBox.baseVal;
          if (box && box.width > 0) { width = box.width; height = box.height; }
          else if (el) { const r = el.getBoundingClientRect(); width = r.width; height = r.height; }
          holder.innerHTML = '';
          return { svg, width, height };
        } catch (e) {
          for (const n of document.querySelectorAll('#' + id + ', #d' + id)) n.remove();
          return { error: String((e && (e.message || e.str)) || e) };
        }
      }
    };
    """
}
