import AppKit
import CoreText
import SwiftMath
import SwiftUI
import XCTest
@testable import kk

final class LaTeXCompatibilityTests: XCTestCase {
    /// LaTeX that SwiftMath 1.7 rejects on its own. Each must parse after rewriting and draw.
    static let unsupported: [String] = [
        #"n \equiv 1 \pmod{10}"#, #"a \bmod b"#, #"x \mod 5"#, #"x \equiv y \pod{7}"#,
        #"\dfrac{a}{b}"#, #"\tfrac{a}{b}"#, #"\dbinom{n}{k}"#, #"\tbinom{n}{k}"#, #"\cfrac{1}{1+\cfrac{1}{x}}"#, #"\dfrac12"#,
        #"\operatorname{rank}(A)"#, #"\operatorname*{arg\,max}_{x \in X} f(x)"#, #"\operatorname{Var}[X]"#,
        #"a \not\equiv b"#, #"a \not= b"#, #"x \not\in S"#, #"a \not\mid b"#,
        #"\big( x \big)"#, #"\Big[ x \Big]"#, #"\bigl( x \bigr)"#, #"\Bigg\{ x \Bigg\}"#, #"\left( a \middle| b \right)"#,
        #"\left\lvert x \right\rvert"#, #"\lvert x \rvert"#, #"\lVert x \rVert"#, #"\left\lbrack x \right\rbrack"#,
        #"1, 2, \dots, n"#, #"a_1 + \dotsb + a_n"#, #"p \implies q"#, #"p \impliedby q"#, #"A \hookrightarrow B"#,
        #"\therefore x"#, #"a \nmid b"#, #"x \leqslant y"#, #"x \geqslant y"#, #"\varnothing"#, #"\iint_D f"#, #"\iiint_V f"#,
        #"\mathscr{L}"#, #"\boldsymbol{x}"#, #"\boldsymbol{\alpha}"#, #"\mathds{1}"#,
        #"\overset{?}{=}"#, #"\underset{\theta}{\arg\min}"#, #"\stackrel{\text{def}}{=}"#, #"\overset{n}{\longrightarrow}"#,
        #"\underbrace{a+b}_{n}"#, #"\overbrace{a+b}^{n}"#, #"\boxed{42}"#, #"\cancel{x}"#, #"\cancelto{0}{x}"#,
        #"\begin{align} a &= b \\ c &= d \end{align}"#, #"\begin{align*} a &= b \\[4pt] c &= d \\ \end{align*}"#,
        #"\begin{aligned} a &= b & c &= d \end{aligned}"#, #"\begin{aligned} a = b \\ c = d \end{aligned}"#,
        #"\begin{aligned} f(x) &= x^2 && \text{by definition} \end{aligned}"#,
        #"\begin{gathered} a \\ b \end{gathered}"#, #"\begin{gather*} a \\ b \end{gather*}"#,
        #"\begin{multline} a \\ b \end{multline}"#, #"\begin{split} a &= b \end{split}"#,
        #"\begin{eqnarray*} a &=& b \\ c &=& d \end{eqnarray*}"#,
        #"\begin{array}{cc} a & b \\ c & d \end{array}"#, #"\left\{\begin{array}{ll} 1 & x > 0 \\ 0 & \text{else} \end{array}\right."#,
        #"\begin{array}{c|c} a & b \\ \hline c & d \end{array}"#, #"\begin{smallmatrix} 1 & 2 \end{smallmatrix}"#,
        #"\begin{pmatrix*}[r] 1 & -2 \end{pmatrix*}"#, #"\begin{dcases} 1 & x > 0 \\ 0 & x \le 0 \end{dcases}"#,
        #"\begin{cases} x \\ y \end{cases}"#, #"\begin{rcases} a \\ b \end{rcases}"#,
        #"\begin{equation} E = mc^2 \end{equation}"#, #"\begin{align} a &= b \label{eq:1} \tag{1} \end{align}"#,
        #"\int_0^1 x\:dx"#, #"\overrightarrow{AB}"#, #"\overleftarrow{AB}"#, #"\phantom{x}y"#, #"a \hspace{1em} b"#,
        #"A \& B"#, #"x \xrightarrow{f} y"#, #"x \xrightarrow[g]{f} y"#, #"\textit{a b}"#, #"\mbox{a b}"#, #"\emph{a}"#,
        #"\textup{a}"#, #"\it a"#, #"\Bbb R"#, #"x \nonumber"#, #"\intertext{so}"#, #"\sum_{\substack{i < n \\ j < m}} a_{ij}"#,
        #"x \subsetneq y"#, #"\nexists x"#, #"\blacksquare"#, #"\Box"#, #"\checkmark"#, #"\lcm(a, b)"#, #"\varkappa"#,
        #"A \rightleftharpoons B"#, #"x \lesssim y"#, #"x \gtrsim y"#, #"a \preceq b"#, #"\Gamma \vdash A"#,
        #"a \lt b \gt c"#, #"x \leqq y"#, #"x \nleq y"#, #"A \nsubseteq B"#, #"x \coloneqq 1"#, #"x \triangleq 1"#,
        #"G \ltimes H"#, #"a \diamond b"#, #"A \smallsetminus B"#, #"\S 3"#, #"\pounds 5"#, #"x \mapsto y \longmapsto z"#,
        #"\llbracket x \rrbracket"#, #"f: A \twoheadrightarrow B"#, #"\sideset{}{}\sum"#.replacingOccurrences(of: #"\sideset{}{}"#, with: ""),
        #"\color{red} x + y"#, #"{\color{blue} a} + b"#, #"\textcolor{green}{x}"#, #"\mathop{\mathrm{sgn}}\limits_x"#,
        #"\mathbin{\triangle}"#, #"\argmax_x f"#, #"\sgn(x)"#, #"\tr(A)"#,
        "f'(x) + f''(x) + g'^2", "x ≤ y ≥ z ≠ w", "α + β = γ", "x ∈ ℝ", "a → b ⇒ c", "x² + y₁", "θ ∈ [0, 2π)",
        "a × b · c", "∀ε > 0 ∃δ", "x ∉ ∅", "∑ᵢ x", "x⁻¹ + aᵢⱼ", "Aᵀ", "A ⊆ B ∪ C", "√2", "90°", "f′(x)", "\\text{don’t — stop}",
    ]

    @MainActor
    func testUnsupportedLaTeXParsesAfterRewriting() {
        var failures: [String] = []
        for source in Self.unsupported {
            for display in [true, false] {
                let rewritten = LaTeXCompatibility.equation(source, display: display)
                if let error = LaTeXCompatibility.error(in: rewritten) {
                    failures.append("\(source) → \(rewritten): \(error)")
                }
            }
        }
        XCTAssertEqual(failures, [])
    }

    @MainActor
    func testRewrittenLaTeXDrawsVisibleMath() throws {
        _ = NSApplication.shared
        var blank: [String] = []
        for source in Self.unsupported {
            let rewritten = LaTeXCompatibility.equation(source, display: true)
            if source == #"\phantom{x}y"# || source == #"x \nonumber"# { continue }
            if try ink(rewritten) == 0 { blank.append(source) }
        }
        XCTAssertEqual(blank, [])
    }

    /// Operators draw a single glyph from SwiftMath's font, with no fallback, so each one must
    /// exist there. Other symbols draw as text and fall back to a system font if needed.
    @MainActor
    func testRegisteredOperatorsHaveGlyphsInTheMathFont() throws {
        let font = try mathFont()
        var missing: [String] = []
        for (name, atom) in LaTeXCompatibility.symbols where atom.type == .largeOperator && atom.nucleus.count == 1 {
            let characters = Array(atom.nucleus.utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            if !CTFontGetGlyphsForCharacters(font, characters, &glyphs, characters.count) { missing.append(name) }
        }
        XCTAssertEqual(missing.sorted(), [], "Pick a different character or drop these symbols")
    }

    @MainActor
    func testRegisteredSymbolsDraw() throws {
        _ = NSApplication.shared
        LaTeXCompatibility.registerSymbols()
        var blank: [String] = []
        for name in LaTeXCompatibility.symbols.keys.sorted() where try ink("\\" + name) == 0 { blank.append(name) }
        XCTAssertEqual(blank, [])
    }

    @MainActor
    func testModularArithmeticUsesAMSSpacing() {
        XCTAssertEqual(LaTeXCompatibility.equation(#"n \equiv 1 \pmod{10}"#, display: true), #"n \equiv 1 \quad(\mathrm{mod}\;10)"#)
        XCTAssertEqual(LaTeXCompatibility.equation(#"n \equiv 1 \pmod{10}"#, display: false), #"n \equiv 1 \>\>(\mathrm{mod}\;10)"#)
        XCTAssertEqual(LaTeXCompatibility.equation(#"a \bmod b"#, display: true), #"a \;\mathrm{mod}\; b"#)
        XCTAssertEqual(LaTeXCompatibility.equation(#"x \equiv y \mod n"#, display: true), #"x \equiv y \quad\mathrm{mod}\,\,n"#)
    }

    @MainActor
    func testRewritesKeepMeaning() {
        func rewrite(_ source: String) -> String { LaTeXCompatibility.equation(source, display: true) }
        XCTAssertEqual(rewrite("f'(x)"), #"f\prime(x)"#)
        XCTAssertEqual(rewrite("f''^2 + g'x"), #"f\prime\prime^2 + g\prime x"#)
        XCTAssertEqual(rewrite(#"\text{don't}"#), #"\text{don't}"#, "Apostrophes in text aren't primes")
        XCTAssertEqual(rewrite(#"a \not\equiv b"#), #"a \nequiv b"#)
        XCTAssertEqual(rewrite(#"\bigl( x \bigr)"#), "( x )")
        XCTAssertEqual(rewrite(#"\big. x"#), " x")
        XCTAssertEqual(rewrite(#"\left\lvert x \right\rvert"#), #"\left| x \right|"#)
        XCTAssertEqual(rewrite("x≤y"), #"x\leq y"#, "A command never runs into the following letter")
        XCTAssertEqual(rewrite("x∈ℝ"), #"x\in\mathbb{R}"#)
        XCTAssertEqual(rewrite("∑ᵢ"), #"\sum_{i}"#)
        XCTAssertEqual(rewrite("x⁻¹ + aᵢⱼ"), #"x^{-1} + a_{ij}"#)
        XCTAssertEqual(rewrite("∀ε"), #"\forall\varepsilon"#)
        XCTAssertEqual(rewrite(#"\text{α particle}"#), #"\text{\alpha particle}"#)
        XCTAssertEqual(rewrite(#"\text{αb}"#), #"\text{\alpha{}b}"#, "Text mode separates with {} so no space appears")
        XCTAssertEqual(rewrite(#"\textbf{a b}"#), #"\textbf{a\ b}"#)
        XCTAssertEqual(rewrite(#"\dfrac{a}{b}"#), #"\left.\displaystyle\frac{a}{b}\right."#)
        XCTAssertEqual(rewrite(#"{\color{red} a} + b"#), #"{\color{#E5484D}{ a}} + b"#, "Color stops at the end of its group")
        XCTAssertEqual(rewrite(#"\color{black}{x}"#), "{x}", "Unknown colors are dropped rather than failing")
        XCTAssertEqual(rewrite("a % comment\n+ b"), "a \n+ b")
        XCTAssertEqual(rewrite(#"\begin{align*} a &= b \\[2pt] c &= d \\ \end{align*}"#), #"\begin{aligned}a & = b \\ c & = d\end{aligned}"#)
        XCTAssertEqual(rewrite(#"\begin{aligned} a &= b & c &= d \end{aligned}"#), #"\begin{aligned}a & = b \qquad c= d\end{aligned}"#)
        XCTAssertEqual(rewrite(#"\begin{aligned} a \\ b \end{aligned}"#), #"\begin{aligned}a &  \\ b & \end{aligned}"#)
        XCTAssertEqual(rewrite(#"\begin{cases} x \\ y \end{cases}"#), #"\begin{cases}x &  \\ y & \end{cases}"#)
        XCTAssertEqual(rewrite(#"\sum_{\substack{i \\ j}}"#), #"\sum_{{{i  \atop  j}}}"#)
        XCTAssertEqual(rewrite(#"\\ [a, b]"#), #"\\ [a, b]"#, "Only spacing is dropped after a row break, not math")
        XCTAssertEqual(rewrite(#"\frac{a}{b} \overline{x} \sqrt[3]{y}"#), #"\frac{a}{b} \overline{x} \sqrt[3]{y}"#, "Supported LaTeX is unchanged")
    }

    /// Wrapping writes math back to LaTeX through SwiftMath's reverse symbol table. Registering
    /// operators must not make ordinary atoms such as `=` come back as operators.
    @MainActor
    func testRegisteredOperatorsKeepTheReverseTableIntact() throws {
        _ = LaTeXCompatibility.equation(#"\overset{?}{=} \operatorname{d} \stackrel{+}{x}"#, display: true)
        let list = try XCTUnwrap(MTMathListBuilder.build(fromString: "a=b+d"))
        XCTAssertEqual(MTMathListBuilder.mathListToString(list), "a=b+d")
    }

    @MainActor
    func testWrappingKeepsRewrittenCommands() throws {
        _ = NSApplication.shared
        let source = LaTeXCompatibility.equation(#"\operatorname{rank}(A) + \dots + a \implies b \pmod{n} + c + d + e + f + g + h"#, display: true)
        let wrapped = LaTeXWrapping.equation(source, width: 200, fontSize: 18)
        XCTAssertTrue(wrapped.contains(#"\begin{gather}"#))
        XCTAssertNil(LaTeXCompatibility.error(in: wrapped))
        XCTAssertEqual(LaTeXWrapping.equation(LaTeXCompatibility.equation(#"\cancel{a+b+c+d+e+f+g+h+i+j+k}"#, display: true), width: 60, fontSize: 18),
                       LaTeXCompatibility.equation(#"\cancel{a+b+c+d+e+f+g+h+i+j+k}"#, display: true), "Colored math isn't reflowed")
    }

    // MARK: - Helpers

    @MainActor
    private func ink(_ latex: String) throws -> Int {
        let label = MTMathUILabel()
        label.latex = latex
        label.fontSize = 24
        label.labelMode = .display
        label.textColor = .black
        XCTAssertNil(label.error, latex)
        let size = label.fittingSize
        guard size.width >= 1 else { return 0 }
        // Padding keeps very flat math such as \dots from being clipped.
        label.frame = NSRect(origin: .zero, size: CGSize(width: ceil(size.width) + 20, height: ceil(size.height) + 40))
        label.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(label.bitmapImageRepForCachingDisplay(in: label.bounds))
        label.cacheDisplay(in: label.bounds, to: bitmap)
        var count = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.2 { count += 1 }
        }
        return count
    }

    private func mathFont() throws -> CTFont {
        let roots = [Bundle(for: Self.self).bundleURL.deletingLastPathComponent(), Bundle.main.bundleURL, Bundle.main.bundleURL.deletingLastPathComponent()]
        let enumeratorRoots = roots.compactMap { FileManager.default.enumerator(at: $0, includingPropertiesForKeys: nil) }
        for enumerator in enumeratorRoots {
            for case let url as URL in enumerator where url.lastPathComponent == "latinmodern-math.otf" {
                let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
                if let descriptor = descriptors?.first { return CTFontCreateWithFontDescriptor(descriptor, 20, nil) }
            }
        }
        throw XCTSkip("SwiftMath's font bundle wasn't found next to the tests")
    }
}

final class MathMarkdownTests: XCTestCase {
    @MainActor
    func testFindsMathLikeMarkdownViewAndSkipsCode() {
        let markdown = """
        Inline $a \\pmod{3}$ and \\(b\\) cost $5 and $10.
        `$x \\pmod 2$` stays code.

        $$
        c \\pmod 4
        $$

        \\[d\\]

        ```
        $$e \\pmod 5$$
        ```

        \\begin{align*} f &= g \\end{align*}
        """
        let segments = MathMarkdown.segments(in: markdown).map { String(markdown[$0.range]) }
        XCTAssertEqual(segments, ["$a \\pmod{3}$", "\\(b\\)", "$$\nc \\pmod 4\n$$", "\\[d\\]", "\\begin{align*} f &= g \\end{align*}"])
    }

    @MainActor
    func testRenderableRewritesMathAndLeavesTheRestAlone() {
        let markdown = "It costs $5 and $10. So $n \\equiv 1 \\pmod{10}$ and\n\n\\begin{align*} a &= b \\end{align*}\n\n`\\pmod` in code."
        XCTAssertEqual(MathMarkdown.renderable(markdown),
                       "It costs $5 and $10. So $n \\equiv 1 \\>\\>(\\mathrm{mod}\\;10)$ and\n\n$$\\begin{aligned}a & = b\\end{aligned}$$\n\n`\\pmod` in code.")
    }

    @MainActor
    func testMathThatStillFailsShowsItsSource() {
        let markdown = "Inline $x \\foo y$ here.\n\n1. Step\n   $$\n   \\bar{x} \\undefinedcommand\n   $$\n2. Next"
        let rendered = MathMarkdown.renderable(markdown)
        XCTAssertEqual(rendered, "Inline `$x \\foo y$` here.\n\n1. Step\n   ```kk-math\n   $$\n   \\bar{x} \\undefinedcommand\n   $$\n   ```\n2. Next")
        let failures = MathMarkdown.failures(in: markdown)
        XCTAssertEqual(failures.map(\.source), ["$x \\foo y$", "$$\n   \\bar{x} \\undefinedcommand\n   $$"])
        XCTAssertEqual(failures.map(\.display), [false, true])
        XCTAssertTrue(failures[0].error.contains("foo"))
    }

    @MainActor
    func testReplacingKeepsDelimitersAndEveryCopy() throws {
        let markdown = "A $x \\foo$ and again $x \\foo$, then \\begin{align*} \\bad \\end{align*}."
        let fixed = try XCTUnwrap(MathMarkdown.replacing("$x \\foo$", withBody: " x \\cdot y \n", in: markdown))
        XCTAssertEqual(fixed, "A $x \\cdot y$ and again $x \\cdot y$, then \\begin{align*} \\bad \\end{align*}.")
        let environment = try XCTUnwrap(MathMarkdown.replacing("\\begin{align*} \\bad \\end{align*}", withBody: "\\begin{aligned} a &= b \\end{aligned}", in: fixed))
        XCTAssertTrue(environment.hasSuffix("then $$\\begin{aligned} a &= b \\end{aligned}$$."))
        XCTAssertNil(MathMarkdown.replacing("$missing$", withBody: "x", in: markdown))
        XCTAssertEqual(MathMarkdown.strippingDelimiters("$$ x $$"), "x")
        XCTAssertEqual(MathMarkdown.strippingDelimiters("\\[x\\]"), "x")
        XCTAssertEqual(MathMarkdown.strippingDelimiters("x"), "x")
    }

    /// A rewritten equation renders in the real answer view, with no parse error.
    @MainActor
    func testAnswerViewRendersRewrittenMath() async throws {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: ResponseView(markdown: "So $n \\equiv 1 \\pmod{10}$.\n\n$$\\dfrac{a}{b} \\implies \\operatorname{rank}(A) \\leqslant n$$", isStreaming: false, textSize: 14)
            .frame(width: 360).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFront(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(400))
        host.layoutSubtreeIfNeeded()
        func views(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(views) }
        let labels = views(host).compactMap { $0 as? MTMathUILabel }
        XCTAssertEqual(labels.count, 2)
        for label in labels {
            XCTAssertNil(label.error, label.latex)
            XCTAssertGreaterThan(label.fittingSize.width, 20)
        }
    }
}

final class EquationRepairTests: XCTestCase {
    @MainActor
    private func makeChat() -> (ChatController, Preferences) {
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.baseURL = "https://fixture.invalid/v1"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MathProtocol.self]
        let chat = ChatController(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(permissionCheck: { false }),
                                  apiClient: OpenAICompatibleClient(session: URLSession(configuration: config)))
        chat.removeScreen()
        MathProtocol.reset()
        return (chat, prefs)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition())
    }

    private static let brokenAnswer = "So $x \\foo y$ holds, and\n\n$$\na \\bar b \\baz\n$$\n\nwith $n \\pmod{3}$ fine."

    @MainActor
    func testBrokenEquationsAreRepairedInOneRequest() async throws {
        let (chat, _) = makeChat()
        MathProtocol.answer = Self.brokenAnswer
        MathProtocol.repairReply = "```latex\nx \\cdot y\n```\n\n```latex\n$$a \\bar{b}$$\n```"
        chat.prompt = "prove it"
        chat.submit()
        try await waitUntil { chat.messages.last?.content.contains("\\cdot") == true }
        XCTAssertEqual(chat.messages.last?.content, "So $x \\cdot y$ holds, and\n\n$$\na \\bar{b}\n$$\n\nwith $n \\pmod{3}$ fine.",
                       "Compatible LaTeX like \\pmod isn't sent or changed")
        XCTAssertEqual(MathProtocol.requests.count, 2, "One answer plus one repair request for both equations")
        let repair = MathProtocol.requests[1]
        XCTAssertTrue(repair.contains("Invalid command \\\\foo"), "The renderer error is sent")
        XCTAssertTrue(repair.contains("a \\\\bar b \\\\baz"), "The broken equation is sent")
        XCTAssertFalse(repair.contains("pmod"), "Equations that render aren't sent")
        XCTAssertTrue(repair.contains("prove it"), "The question gives context")
        try await waitUntil { chat.equationRepairs.statuses.isEmpty }
    }

    @MainActor
    func testInvalidFixIsRejectedAndMarked() async throws {
        let (chat, _) = makeChat()
        MathProtocol.answer = "Then\n\n$$\\foo$$"
        MathProtocol.repairReply = "```latex\n\\stillbroken\n```"
        chat.prompt = "go"
        chat.submit()
        try await waitUntil { if case .failed = chat.equationRepairs.status(for: "$$\\foo$$") { true } else { false } }
        XCTAssertEqual(chat.messages.last?.content, "Then\n\n$$\\foo$$")
        XCTAssertEqual(MathProtocol.requests.count, 2, "Only one automatic attempt")
    }

    @MainActor
    func testRepairOffSendsNothingUntilTheUserAsks() async throws {
        let (chat, prefs) = makeChat()
        prefs.repairMath = false
        MathProtocol.answer = "Then\n\n$$\\foo$$"
        MathProtocol.repairReply = "```latex\nx\n```"
        chat.prompt = "go"
        chat.submit()
        try await waitUntil { !chat.isStreaming }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(MathProtocol.requests.count, 1)
        XCTAssertTrue(chat.equationRepairs.statuses.isEmpty)

        chat.repairEquation("$$\\foo$$")
        try await waitUntil { chat.messages.last?.content == "Then\n\n$$x$$" }
        XCTAssertEqual(MathProtocol.requests.count, 2)
    }

    @MainActor
    func testValidMathSendsNoRepair() async throws {
        let (chat, _) = makeChat()
        MathProtocol.answer = "Fine: $\\dfrac{1}{2} \\pmod 3$ and $$\\operatorname{rank}(A)$$"
        chat.prompt = "go"
        chat.submit()
        try await waitUntil { !chat.isStreaming }
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(MathProtocol.requests.count, 1)
    }
}

private final class MathProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var answer = "Plain answer."
    nonisolated(unsafe) static var repairReply = ""
    nonisolated(unsafe) static var requests: [String] = []
    private static let lock = NSLock()

    static func reset() {
        lock.withLock { answer = "Plain answer."; repairReply = ""; requests = [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let body = Self.body(of: request)
        let reply: String = Self.lock.withLock {
            Self.requests.append(body)
            return body.contains("fail to render") || body.contains("fails to render") ? Self.repairReply : Self.answer
        }
        let chunk = try! JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": reply]]]])
        let stream = "data: \(String(decoding: chunk, as: UTF8.self))\n\ndata: [DONE]\n\n"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stream.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func body(of request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
