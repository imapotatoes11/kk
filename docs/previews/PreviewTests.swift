// Documentation authoring fixture. Copied into an isolated package by render-previews.sh.
// Uses production views and ChatController, but never reads the desktop or real API keys.
import AppKit
import PDFKit
import SwiftUI
import SwiftMath
import XCTest
@testable import kk

final class DocumentationPreviewTests: XCTestCase {
    @MainActor
    func testRenderPreviews() async throws {
        let output = try XCTUnwrap(ProcessInfo.processInfo.environment["KK_PREVIEW_DIR"])
        _ = NSApplication.shared
        let pdfPath = try XCTUnwrap(ProcessInfo.processInfo.environment["KK_PROBLEM_SET_PDF"])
        let problemSet = try XCTUnwrap(PDFDocument(url: URL(fileURLWithPath: pdfPath)))
        XCTAssertEqual(problemSet.pageCount, 2)
        XCTAssertTrue(problemSet.page(at: 1)?.string?.contains("Logarithmic moments") == true)
        let suite = "kk.documentation-preview.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        preferences.baseURL = "https://preview.invalid/first/v1"
        preferences.model = "documentation-fixture"
        preferences.appearance = .light
        preferences.popupMaterial = .opaque
        preferences.annotationTool = .ellipse
        preferences.accent = .system
        let document = AnnotationDocument()
        document.isFrozen = true
        document.begin(at: CGPoint(x: 289, y: 601), tool: .ellipse, color: .red, lineWidth: 3)
        document.move(to: CGPoint(x: 377, y: 635))
        document.finish()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PreviewResponse.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let stage = NSHostingView(rootView: Workspace(document: document, example: .code))
        let window = mount(stage, size: NSSize(width: 1440, height: 900))
        defer { window.close() }
        try await settle(stage)
        let screen = try ImageProcessor.jpegData(from: bitmap(stage).cgImage!)
        let chat = ChatController(preferences: preferences, keychain: PreviewKeychain(),
            captureService: ScreenCaptureService(permissionCheck: { false }),
            apiClient: OpenAICompatibleClient(session: session), initialScreenContext: .ready(screen))
        chat.screenCaptureSuspended = true
        let controller = PanelController(preferences: preferences)
        let scene = PreviewScene(chat: chat, preferences: preferences, controller: controller, document: document)
        let host = NSHostingView(rootView: scene)
        window.contentView = host
        window.setContentSize(NSSize(width: 1440, height: 900))
        chat.prompt = "Why does the second call keep the first tag?"
        try await settle(host)
        try save(host, to: output, name: "annotate")
        chat.submit()
        try await completed(chat)
        chat.prompt = "Show the safe version."
        try await settle(host)
        try save(host, to: output, name: "screen-context")
        preferences.appearance = .dark
        host.appearance = NSAppearance(named: .darkAqua)
        try await settle(host)
        try save(host, to: output, name: "screen-context-dark")
        preferences.appearance = .light
        host.appearance = NSAppearance(named: .aqua)
        preferences.baseURL = "https://preview.invalid/followup/v1"
        // The follow-up retains the first turn's attached screen in conversation history.
        // No screen capture or permission request occurs in this authoring fixture.
        chat.submit()
        try await completed(chat)
        try await settle(host)
        try save(host, to: output, name: "follow-up")
        XCTAssertEqual(chat.messages.filter { $0.role == .user }.count, 2)
        XCTAssertEqual(chat.messages.first?.screenData, screen)
        XCTAssertEqual(chat.messages.last?.content, PreviewResponse.followup)
        chat.reset()

        // A second scenario demonstrates actual LaTeX and a changed attachment on turn two.
        document.clear()
        document.begin(at: CGPoint(x: 240, y: 511), tool: .ellipse, color: .red, lineWidth: 3)
        document.move(to: CGPoint(x: 565, y: 571))
        document.finish()
        let mathStage = NSHostingView(rootView: Workspace(document: document, example: .math))
        let mathWindow = mount(mathStage, size: NSSize(width: 1440, height: 900))
        defer { mathWindow.close() }
        try await settle(mathStage)
        let mathImage = try XCTUnwrap(bitmap(mathStage).cgImage)
        let mathScreen = try ImageProcessor.jpegData(from: mathImage)
        let snapshot = ScreenSnapshot(image: mathImage, data: mathScreen)
        preferences.baseURL = "https://preview.invalid/math-first/v1"
        let mathChat = ChatController(preferences: preferences, keychain: PreviewKeychain(),
            captureService: ScreenCaptureService(permissionCheck: { true }),
            apiClient: OpenAICompatibleClient(session: session), initialScreenContext: .ready(mathScreen),
            capture: { _ in snapshot })
        mathChat.screenCaptureSuspended = true
        let mathHost = NSHostingView(rootView: PreviewScene(chat: mathChat, preferences: preferences,
            controller: controller, document: document, example: .math))
        window.contentView = mathHost
        window.setContentSize(NSSize(width: 1440, height: 900))
        mathChat.prompt = "How do I evaluate the circled integral?"
        try await settle(mathHost)
        try save(mathHost, to: output, name: "math-annotate")
        mathChat.submit()
        try await completed(mathChat)
        try await settle(mathHost)
        try save(mathHost, to: output, name: "math-context")

        // Move and resize the original mark, using the app's annotation transform operation.
        document.beginTransform()
        document.replace(at: 0, with: ScreenAnnotation(tool: .ellipse, color: .red, lineWidth: 3,
            points: [CGPoint(x: 257, y: 423), CGPoint(x: 365, y: 483)]))
        mathChat.screenCaptureSuspended = false
        mathChat.beginCapture(for: try XCTUnwrap(NSScreen.main))
        for _ in 0..<100 {
            if case .ready = mathChat.screenContextState { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        mathChat.screenCaptureSuspended = true
        try await settle(mathStage)
        let changedScreen = try ImageProcessor.jpegData(from: XCTUnwrap(bitmap(mathStage).cgImage))
        mathChat.prepareScreen = { _ in changedScreen }
        mathChat.preparePreview = { _ in changedScreen }
        mathChat.prompt = "Evaluate the newly circled case."
        preferences.baseURL = "https://preview.invalid/math-followup/v1"
        try await settle(mathHost)
        try save(mathHost, to: output, name: "math-reannotate")
        mathChat.submit()
        // Screen preparation runs before generation starts.
        for _ in 0..<100 {
            if mathChat.messages.count == 4 { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        try await completed(mathChat)
        try await settle(mathHost)
        try save(mathHost, to: output, name: "math-follow-up")
        let questions = mathChat.messages.filter { $0.role == .user }
        XCTAssertEqual(questions.count, 2)
        XCTAssertEqual(questions.first?.screenData, mathScreen)
        XCTAssertEqual(questions.last?.screenData, changedScreen)
        XCTAssertNotEqual(mathScreen, changedScreen)
        XCTAssertEqual(mathChat.messages.last?.content, PreviewResponse.mathFollowup)
        let mathLabels = descendants(mathHost).compactMap { $0 as? MTMathUILabel }
        XCTAssertGreaterThanOrEqual(mathLabels.count, 2)
        for label in mathLabels { XCTAssertNil(label.error) }
        mathChat.reset()
    }

    @MainActor private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }

    @MainActor private func completed(_ chat: ChatController) async throws {
        for _ in 0..<100 {
            if !chat.isStreaming { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        XCTAssertFalse(chat.isStreaming)
        if case .error(let error) = chat.generationState { XCTFail(error.localizedDescription) }
    }

    @MainActor private func mount<Content: View>(_ host: NSHostingView<Content>, size: NSSize) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        host.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.orderFront(nil)
        return window
    }

    @MainActor private func settle(_ view: NSView) async throws {
        try await Task.sleep(for: .milliseconds(700))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
    }

    @MainActor private func bitmap(_ view: NSView) throws -> NSBitmapImageRep {
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep
    }

    @MainActor private func save(_ view: NSView, to directory: String, name: String) throws {
        let url = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let png = try XCTUnwrap(bitmap(view).representation(using: .png, properties: [:]))
        try png.write(to: url.appendingPathComponent(name + ".png"))
    }
}

private struct PreviewKeychain: APIKeyStoring {
    func loadAPIKey() -> String? { nil }
    func saveAPIKey(_ value: String) throws {}
    func deleteAPIKey() throws {}
}

private final class PreviewResponse: URLProtocol, @unchecked Sendable {
    static let first = """
    `tags=[]` creates one list when the function is defined. Each call that omits `tags` reuses that same list.

    So the second call appends `"review"` to the list that already contains `"draft"`. Both variables reference it.

    Use `None` as the default and create a fresh list inside the function.
    """
    static let followup = """
    ```python
    def add_tag(tag, tags=None):
        if tags is None:
            tags = []
        tags.append(tag)
        return tags
    ```

    Now each call without a list starts fresh: `['draft']`, then `['review']`.
    """
    static let mathFirst = #"""
    Differentiate $\int_0^1 x^n\,dx=1/(n+1)$ with respect to $n$:

    $$I_n=\int_0^1 x^n\ln x\,dx=-\frac{1}{(n+1)^2}.$$

    Valid for $n>-1$. The result is negative because $\ln x<0$ on $(0,1)$.
    """#
    static let mathFollowup = #"""
    The circle now marks $n=2$. Substitute it into the formula:

    $$I_2=\int_0^1 x^2\ln x\,dx=-\frac{1}{(2+1)^2}=-\frac{1}{9}.$$
    """#
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        let text = path.contains("math-followup") ? Self.mathFollowup :
            path.contains("math-first") ? Self.mathFirst :
            path.contains("followup") ? Self.followup : Self.first
        let event: [String: Any] = ["choices": [["delta": ["content": text]]]]
        let data = try! JSONSerialization.data(withJSONObject: event)
        let body = "data: " + String(decoding: data, as: UTF8.self) + "\n\ndata: [DONE]\n\n"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private struct PreviewScene: View {
    @ObservedObject var chat: ChatController
    @ObservedObject var preferences: Preferences
    let controller: PanelController
    @ObservedObject var document: AnnotationDocument
    var example: PreviewExample = .code
    private var followup: Bool { chat.messages.count > 2 }
    var body: some View {
        ZStack(alignment: .topLeading) {
            Workspace(document: document, example: example)
            VStack(spacing: 12) {
                PanelRootView(chat: chat, preferences: preferences, panelController: controller, onOpenSettings: {}, onDismiss: {})
                    .frame(width: 600, height: chat.hasSubmitted ? (followup ? 662 : example == .math ? 410 : 360) : 140)
                    .shadow(color: .black.opacity(0.16), radius: 24, y: 10)
                if !chat.hasSubmitted || (example == .math && !followup && !chat.prompt.isEmpty) {
                    AnnotationToolbar(document: document, preferences: preferences, onFocus: {}, onClear: {})
                        .frame(width: 600)
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 6)
                }
            }
            .environment(\.colorScheme, preferences.appearance == .dark ? .dark : .light)
            .offset(x: 792, y: 100)
        }
        .frame(width: 1440, height: 900)
    }
}

private enum PreviewExample { case code, math }

// Fictional window content supplies safe, repeatable screen context.
private struct Workspace: View {
    private let ink = Color(red: 0.16, green: 0.22, blue: 0.23)
    private let lines = [
        "# A tiny helper for review labels", "", "def add_tag(tag, tags=[]):",
        "    tags.append(tag)", "    return tags", "", "first = add_tag(\"draft\")",
        "second = add_tag(\"review\")", "", "print(first)", "print(second)"
    ]
    @ObservedObject var document: AnnotationDocument
    let example: PreviewExample
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.968, green: 0.977, blue: 0.974)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.28), Color(red: 0.22, green: 0.77, blue: 0.35)], id: \.self) { color in
                        Circle().fill(color).frame(width: 11, height: 11)
                    }
                    Spacer()
                    Text(example == .code ? "review.py" : "problem-set-4.pdf").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "sidebar.right").foregroundStyle(.secondary)
                }.padding(.horizontal, 18).frame(height: 48).background(Color(red: 0.96, green: 0.97, blue: 0.96))
                Divider()
                if example == .code {
                    HStack {
                        Image(systemName: "chevron.left.forwardslash.chevron.right").foregroundStyle(Color(red: 0.28, green: 0.48, blue: 0.43))
                        Text("examples / review.py").font(.system(size: 12))
                        Spacer()
                        Text("Python").font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 22).frame(height: 42)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            HStack(spacing: 20) {
                                Text(String(index + 1)).foregroundStyle(.gray).frame(width: 26, alignment: .trailing)
                                Text(line.isEmpty ? " " : line)
                                    .foregroundStyle(index == 0 ? Color.gray : ink)
                                Spacer(minLength: 0)
                            }.font(.system(size: 18, design: .monospaced)).frame(height: 30)
                        }
                    }.padding(.top, 16).padding(.horizontal, 18)
                    Spacer(minLength: 16)
                    Divider()
                    VStack(alignment: .leading, spacing: 15) {
                        Text("OUTPUT").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
                        Text("['draft', 'review']\n['draft', 'review']")
                            .font(.system(size: 17, design: .monospaced)).lineSpacing(8).foregroundStyle(ink)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(24)
                    HStack {
                        Image(systemName: "checkmark.circle"); Text("Process finished")
                        Spacer(); Text("UTF-8     Python 3")
                    }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 20).frame(height: 30).background(Color.black.opacity(0.025))
                } else {
                    HStack(spacing: 18) {
                        Image(systemName: "sidebar.left")
                        Text("2 of 2").font(.system(size: 12))
                        Spacer()
                        Image(systemName: "minus.magnifyingglass")
                        Text("100%").font(.system(size: 12))
                        Image(systemName: "plus.magnifyingglass")
                        Divider().frame(height: 18)
                        Image(systemName: "square.and.arrow.up")
                    }.foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 38)
                        .background(Color(nsColor: .windowBackgroundColor))
                    Divider()
                    AcademicProblemPDF()
                }
            }
            .frame(width: 722, height: 650)
            .background(Color(red: 0.99, green: 0.99, blue: 0.98))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.12)) }
            .shadow(color: .black.opacity(0.10), radius: 24, y: 12)
            .offset(x: 48, y: 100)
            NativePreviewAnnotation(annotations: document.annotations).frame(width: 1440, height: 900)
        }.frame(width: 1440, height: 900).environment(\.colorScheme, .light)
    }

}

// Native scroll viewport drawing PDFKit pages directly. PDFView's tiled layers
// are blank in AppKit bitmap exports, so use PDFPage.draw for reliable snapshots.
private struct AcademicProblemPDF: NSViewRepresentable {
    func makeNSView(context: Context) -> NSScrollView {
        let view = NSScrollView()
        view.hasVerticalScroller = true
        view.hasHorizontalScroller = false
        view.autohidesScrollers = false
        view.scrollerStyle = .legacy
        view.borderType = .noBorder
        view.drawsBackground = true
        view.backgroundColor = NSColor(white: 0.89, alpha: 1)
        let pages = PageCanvas(frame: NSRect(x: 0, y: 0, width: 722, height: 1620))
        if let path = ProcessInfo.processInfo.environment["KK_PROBLEM_SET_PDF"] {
            pages.document = PDFDocument(url: URL(fileURLWithPath: path))
        }
        view.documentView = pages
        return view
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        DispatchQueue.main.async {
            guard let pages = view.documentView as? PageCanvas else { return }
            pages.frame.size.width = view.contentSize.width
            // Page 2 begins at 816 pt. Scroll 142 pt into it, to the end of Problem 4.
            view.contentView.scroll(to: NSPoint(x: 0, y: 958))
            view.reflectScrolledClipView(view.contentView)
            pages.needsDisplay = true
        }
    }

    final class PageCanvas: NSView {
        var document: PDFDocument?
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext,
                  let document else { return }
            NSColor(white: 0.89, alpha: 1).setFill()
            bounds.fill()
            for index in 0..<document.pageCount {
                guard let page = document.page(at: index) else { continue }
                let rect = NSRect(x: (bounds.width - 612) / 2, y: 12 + CGFloat(index) * 804,
                    width: 612, height: 792)
                NSColor.white.setFill()
                rect.fill()
                context.saveGState()
                context.translateBy(x: rect.minX, y: rect.maxY)
                context.scaleBy(x: 1, y: -1)
                page.draw(with: .mediaBox, to: context)
                context.restoreGState()
            }
        }
    }
}

private struct NativePreviewAnnotation: NSViewRepresentable {
    let annotations: [ScreenAnnotation]
    func makeNSView(context: Context) -> MarkView { MarkView() }
    func updateNSView(_ view: MarkView, context: Context) {
        view.annotations = annotations
        view.needsDisplay = true
    }

    final class MarkView: NSView {
        var annotations: [ScreenAnnotation] = []
        override func draw(_ dirtyRect: NSRect) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            AnnotationRenderer.draw(annotations, in: context)
        }
    }
}
