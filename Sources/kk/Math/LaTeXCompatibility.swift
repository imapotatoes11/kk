import Foundation
import SwiftMath

/// Rewrites common LaTeX that SwiftMath can't parse into markup it can render, keeping the
/// meaning. Only the rendered copy changes; copied and requested Markdown stay as written.
///
/// Argument-free symbols (`\dots`, `\implies`, `\nmid`, …) are registered with SwiftMath once.
/// Commands with arguments (`\pmod{n}`, `\dfrac`, `\operatorname`, …), unsupported
/// environments (`align*`, `array`, …), primes and Unicode math characters are rewritten.
@MainActor
enum LaTeXCompatibility {
    /// Returns `source` rewritten for SwiftMath. `display` selects display-math spacing.
    static func equation(_ source: String, display: Bool) -> String {
        registerSymbols()
        var rewriter = Rewriter(tokens: Tokenizer.tokens(source), display: display)
        return rewriter.run(textMode: false)
    }

    /// SwiftMath's parse error for the rewritten source, or nil when it renders.
    static func error(in rewritten: String) -> String? {
        registerSymbols()
        var error: NSError?
        let list = MTMathListBuilder.build(fromString: rewritten, error: &error)
        if let error { return error.localizedDescription }
        return list == nil ? "Couldn't parse this equation" : nil
    }

    // MARK: - Symbols

    private static var registered = false

    static func registerSymbols() {
        guard !registered else { return }
        registered = true
        for (name, atom) in symbols { MTMathAtomFactory.add(latexSymbol: name, value: atom) }
    }

    /// SwiftMath's atom initializer is internal, so new symbols start from a public factory atom.
    nonisolated private static func atom(_ type: MTMathAtomType, _ value: String) -> MTMathAtom {
        let atom = MTMathAtomFactory.atom(forCharacter: "x")!
        atom.type = type
        atom.nucleus = value
        return atom
    }

    /// Symbols missing from SwiftMath 1.7. Values are Unicode characters in Latin Modern Math.
    static let symbols: [String: MTMathAtom] = {
        var table: [String: MTMathAtom] = [:]
        func add(_ type: MTMathAtomType, _ pairs: [(String, String)]) {
            for (name, value) in pairs { table[name] = atom(type, value) }
        }
        add(.ordinary, [
            ("dots", "\u{2026}"), ("dotsc", "\u{2026}"), ("dotso", "\u{2026}"), ("hdots", "\u{2026}"),
            ("mathellipsis", "\u{2026}"), ("dotsb", "\u{22EF}"), ("dotsm", "\u{22EF}"), ("dotsi", "\u{22EF}"),
            ("iddots", "\u{22F0}"), ("varnothing", "\u{2205}"), ("nexists", "\u{2204}"),
            ("blacksquare", "\u{25A0}"), ("Box", "\u{25A1}"), ("checkmark", "\u{2713}"), ("surd", "\u{221A}"),
            ("flat", "\u{266D}"), ("sharp", "\u{266F}"), ("natural", "\u{266E}"), ("clubsuit", "\u{2663}"),
            ("spadesuit", "\u{2660}"), ("heartsuit", "\u{2661}"), ("diamondsuit", "\u{2662}"),
            ("S", "\u{00A7}"), ("P", "\u{00B6}"), ("copyright", "\u{00A9}"), ("pounds", "\u{00A3}"),
            ("yen", "\u{00A5}"), ("euro", "\u{20AC}"), ("varkappa", "\u{03F0}"), ("digamma", "\u{03DD}"),
            ("beth", "\u{2136}"), ("gimel", "\u{2137}"), ("daleth", "\u{2138}"), ("eth", "\u{00F0}"),
            ("complement", "\u{2201}"), ("backprime", "\u{2035}"), ("lozenge", "\u{25CA}"),
            ("blacklozenge", "\u{29EB}"), ("bigstar", "\u{2605}"), ("measuredangle", "\u{2221}"),
            ("sphericalangle", "\u{2222}"), ("diagup", "\u{2571}"), ("diagdown", "\u{2572}"),
            ("Diamond", "\u{22C4}"), ("maltese", "\u{2720}"), ("And", "&"), ("triangledown", "\u{25BD}"),
            ("blacktriangle", "\u{25B4}"), ("blacktriangledown", "\u{25BE}"), ("Finv", "\u{2132}"), ("Game", "\u{2141}"),
        ])
        add(.relation, [
            ("implies", "\u{27F9}"), ("impliedby", "\u{27F8}"), ("hookrightarrow", "\u{21AA}"),
            ("hookleftarrow", "\u{21A9}"), ("rightleftharpoons", "\u{21CC}"), ("leftrightharpoons", "\u{21CB}"),
            ("rightharpoonup", "\u{21C0}"), ("rightharpoondown", "\u{21C1}"), ("leftharpoonup", "\u{21BC}"),
            ("leftharpoondown", "\u{21BD}"), ("upharpoonright", "\u{21BE}"), ("upharpoonleft", "\u{21BF}"),
            ("downharpoonright", "\u{21C2}"), ("downharpoonleft", "\u{21C3}"),
            ("longmapsto", "\u{27FC}"), ("leadsto", "\u{21DD}"), ("nRightarrow", "\u{21CF}"),
            ("nLeftarrow", "\u{21CD}"), ("nLeftrightarrow", "\u{21CE}"), ("nrightarrow", "\u{219B}"),
            ("nleftarrow", "\u{219A}"), ("nleftrightarrow", "\u{21AE}"), ("twoheadrightarrow", "\u{21A0}"),
            ("twoheadleftarrow", "\u{219E}"), ("rightarrowtail", "\u{21A3}"), ("leftarrowtail", "\u{21A2}"),
            ("leftrightarrows", "\u{21C6}"), ("rightleftarrows", "\u{21C4}"), ("rightrightarrows", "\u{21C9}"),
            ("leftleftarrows", "\u{21C7}"), ("upuparrows", "\u{21C8}"), ("downdownarrows", "\u{21CA}"),
            ("curvearrowright", "\u{21B7}"), ("curvearrowleft", "\u{21B6}"), ("circlearrowright", "\u{21BB}"),
            ("circlearrowleft", "\u{21BA}"), ("Lsh", "\u{21B0}"), ("Rsh", "\u{21B1}"),
            ("dashrightarrow", "\u{21E2}"), ("dashleftarrow", "\u{21E0}"), ("Lleftarrow", "\u{21DA}"),
            ("Rrightarrow", "\u{21DB}"), ("rightsquigarrow", "\u{21DD}"), ("leftrightsquigarrow", "\u{21AD}"),
            ("therefore", "\u{2234}"), ("because", "\u{2235}"), ("nmid", "\u{2224}"), ("nparallel", "\u{2226}"),
            ("nleq", "\u{2270}"), ("ngeq", "\u{2271}"), ("nless", "\u{226E}"), ("ngtr", "\u{226F}"),
            ("nsubseteq", "\u{2288}"), ("nsupseteq", "\u{2289}"), ("nsubset", "\u{2284}"), ("nsupset", "\u{2285}"),
            ("subsetneq", "\u{228A}"), ("supsetneq", "\u{228B}"), ("nsim", "\u{2241}"), ("ncong", "\u{2247}"),
            ("nequiv", "\u{2262}"), ("napprox", "\u{2249}"), ("nsimeq", "\u{2244}"), ("nasymp", "\u{226D}"),
            ("nni", "\u{220C}"), ("nprec", "\u{2280}"), ("nsucc", "\u{2281}"), ("nvdash", "\u{22AC}"),
            ("nvDash", "\u{22AD}"), ("nVdash", "\u{22AE}"), ("leqslant", "\u{2A7D}"), ("geqslant", "\u{2A7E}"),
            ("leqq", "\u{2266}"), ("geqq", "\u{2267}"), ("lneq", "\u{2A87}"), ("gneq", "\u{2A88}"),
            ("lneqq", "\u{2268}"), ("gneqq", "\u{2269}"), ("lesssim", "\u{2272}"), ("gtrsim", "\u{2273}"),
            ("lessapprox", "\u{2A85}"), ("gtrapprox", "\u{2A86}"), ("lessgtr", "\u{2276}"), ("gtrless", "\u{2277}"),
            ("preceq", "\u{2AAF}"), ("succeq", "\u{2AB0}"), ("precsim", "\u{227E}"), ("succsim", "\u{227F}"),
            ("preccurlyeq", "\u{227C}"), ("succcurlyeq", "\u{227D}"), ("vdash", "\u{22A2}"), ("dashv", "\u{22A3}"),
            ("vDash", "\u{22A8}"), ("Vdash", "\u{22A9}"), ("Vvdash", "\u{22AA}"), ("coloneqq", "\u{2254}"),
            ("eqqcolon", "\u{2255}"), ("coloneq", "\u{2254}"), ("Coloneqq", "\u{2A74}"), ("triangleq", "\u{225C}"),
            ("approxeq", "\u{224A}"), ("backsim", "\u{223D}"), ("backsimeq", "\u{22CD}"),
            ("bowtie", "\u{22C8}"), ("Join", "\u{22C8}"), ("smile", "\u{2323}"),
            ("frown", "\u{2322}"), ("lt", "<"), ("gt", ">"), ("lll", "\u{22D8}"), ("ggg", "\u{22D9}"),
            ("lhd", "\u{22B2}"), ("rhd", "\u{22B3}"), ("unlhd", "\u{22B4}"), ("unrhd", "\u{22B5}"),
            ("vartriangleleft", "\u{22B2}"), ("vartriangleright", "\u{22B3}"), ("trianglelefteq", "\u{22B4}"),
            ("trianglerighteq", "\u{22B5}"), ("ntriangleleft", "\u{22EA}"), ("ntriangleright", "\u{22EB}"),
            ("multimap", "\u{22B8}"), ("pitchfork", "\u{22D4}"), ("between", "\u{226C}"), ("Subset", "\u{22D0}"),
            ("Supset", "\u{22D1}"), ("eqsim", "\u{2242}"), ("doteqdot", "\u{2251}"), ("Doteq", "\u{2251}"),
            ("risingdotseq", "\u{2253}"), ("fallingdotseq", "\u{2252}"), ("circeq", "\u{2257}"), ("bumpeq", "\u{224F}"),
            ("Bumpeq", "\u{224E}"), ("eqcirc", "\u{2256}"),
            ("sqsubsetneq", "\u{22E4}"), ("sqsupsetneq", "\u{22E5}"), ("subseteqq", "\u{2AC5}"), ("supseteqq", "\u{2AC6}"),
            ("Longmapsto", "\u{27FE}"), ("mapsfrom", "\u{21A4}"),
        ])
        add(.binaryOperator, [
            ("ltimes", "\u{22C9}"), ("rtimes", "\u{22CA}"), ("leftthreetimes", "\u{22CB}"),
            ("rightthreetimes", "\u{22CC}"), ("diamond", "\u{22C4}"), ("smallsetminus", "\u{2216}"),
            ("circledast", "\u{229B}"), ("circledcirc", "\u{229A}"), ("circleddash", "\u{229D}"),
            ("boxplus", "\u{229E}"), ("boxminus", "\u{229F}"), ("boxtimes", "\u{22A0}"), ("boxdot", "\u{22A1}"),
            ("dotplus", "\u{2214}"), ("divideontimes", "\u{22C7}"), ("intercal", "\u{22BA}"),
            ("barwedge", "\u{22BC}"), ("veebar", "\u{22BB}"), ("curlywedge", "\u{22CF}"), ("curlyvee", "\u{22CE}"),
            ("Cap", "\u{22D2}"), ("Cup", "\u{22D3}"), ("bigtriangledown", "\u{25BD}"), ("triangleleft", "\u{25C1}"),
            ("triangleright", "\u{25B7}"), ("bigcirc", "\u{25EF}"), ("doublebarwedge", "\u{2A5E}"),
        ])
        add(.open, [("llbracket", "\u{27E6}"), ("ulcorner", "\u{231C}"), ("llcorner", "\u{231E}")])
        add(.close, [("rrbracket", "\u{27E7}"), ("urcorner", "\u{231D}"), ("lrcorner", "\u{231F}")])
        for (name, value) in [("iint", "\u{222C}"), ("iiint", "\u{222D}"), ("iiiint", "\u{2A0C}"), ("oiint", "\u{222F}"),
                              ("oiiint", "\u{2230}")] {
            table[name] = MTMathAtomFactory.operatorWithName(value, limits: false)
        }
        // Operators models often use without declaring them.
        for name in ["lcm", "sgn", "tr", "Tr", "rank", "diag", "Var", "Cov", "erf", "sech", "csch",
                     "arccot", "arcsec", "arccsc", "Res", "Span", "supp", "proj", "Ker", "Hom", "End", "Aut", "id"] {
            table[name] = MTMathAtomFactory.operatorWithName(name, limits: false)
        }
        for name in ["argmax", "argmin"] {
            table[name] = MTMathAtomFactory.operatorWithName(name == "argmax" ? "arg\u{2009}max" : "arg\u{2009}min", limits: true)
        }
        return table
    }()

    /// Named operators created on demand, such as `\operatorname{rank}`. The zero-width word
    /// joiner keeps each nucleus distinct from ordinary atoms, so SwiftMath's reverse lookup
    /// (used when wrapping) never turns a plain `=` or `d` into one of these operators.
    static func operatorCommand(nucleus: String, limits: Bool) -> String {
        registerSymbols()
        let value = nucleus + "\u{2060}"
        let name = "kkop" + (limits ? "l" : "n") + value.unicodeScalars.map { scalar in
            String(String(scalar.value, radix: 16).map { Character(UnicodeScalar(UInt8(Int(String($0), radix: 16)! + 97))) })
        }.joined(separator: "z")
        if MTMathAtomFactory.atom(forLatexSymbol: name) == nil {
            MTMathAtomFactory.add(latexSymbol: name, value: MTMathAtomFactory.operatorWithName(value, limits: limits))
        }
        return name
    }

    // MARK: - Tokens

    enum Token: Equatable {
        /// A control sequence without its backslash: `frac`, `,`, `\`.
        case command(String)
        case character(Character)

        var isSpace: Bool { if case .character(let c) = self { c.isWhitespace } else { false } }
        func `is`(_ c: Character) -> Bool { self == .character(c) }
        func `is`(command name: String) -> Bool { self == .command(name) }

        var latex: String {
            switch self {
            case .command(let name): "\\" + name
            case .character(let c): String(c)
            }
        }
    }

    enum Tokenizer {
        static func tokens(_ source: String) -> [Token] {
            var tokens: [Token] = []
            let characters = Array(source)
            var index = 0
            while index < characters.count {
                let c = characters[index]
                if c == "\\" {
                    index += 1
                    guard index < characters.count else { tokens.append(.character("\\")); break }
                    if characters[index].isASCIILetter {
                        var name = ""
                        while index < characters.count, characters[index].isASCIILetter { name.append(characters[index]); index += 1 }
                        tokens.append(.command(name))
                    } else {
                        tokens.append(.command(String(characters[index])))
                        index += 1
                    }
                } else if c == "%" {
                    // A comment runs to the end of the line.
                    while index < characters.count, characters[index] != "\n" { index += 1 }
                } else {
                    tokens.append(.character(c))
                    index += 1
                }
            }
            return tokens
        }
    }

    // MARK: - Rewriting

    @MainActor
    struct Rewriter {
        var tokens: [Token]
        var index = 0
        let display: Bool
        private var output = ""
        /// Set after `\name`, so a following letter is separated from the command.
        private var needsSeparator = false
        private var textMode = false

        init(tokens: [Token], display: Bool) {
            self.tokens = tokens
            self.display = display
        }

        mutating func run(textMode: Bool) -> String {
            self.textMode = textMode
            while index < tokens.count { step() }
            return output
        }

        // MARK: Output

        private mutating func emit(_ text: String) {
            guard let first = text.first else { return }
            // SwiftMath reads any Unicode letter as part of a command name.
            if needsSeparator, first.isLetter { output += textMode ? "{}" : " " }
            output += text
            needsSeparator = text.last!.isASCIILetter && Self.endsWithCommand(text)
        }

        private static func endsWithCommand(_ text: String) -> Bool {
            guard let slash = text.lastIndex(of: "\\") else { return false }
            return text[text.index(after: slash)...].allSatisfy(\.isASCIILetter)
        }

        private mutating func emit(command name: String) { emit("\\" + name) }

        private func rewritten(_ tokens: [Token], textMode: Bool = false) -> String {
            var nested = Rewriter(tokens: tokens, display: display)
            return nested.run(textMode: textMode)
        }

        // MARK: Reading

        private var peek: Token? { index < tokens.count ? tokens[index] : nil }

        private mutating func skipSpaces() {
            while let token = peek, token.isSpace { index += 1 }
        }

        private func nextNonSpace(from start: Int) -> Int? {
            var i = start
            while i < tokens.count, tokens[i].isSpace { i += 1 }
            return i < tokens.count ? i : nil
        }

        /// A braced group's contents, or the next single token.
        private mutating func readArgument() -> [Token]? {
            skipSpaces()
            guard let token = peek else { return nil }
            index += 1
            guard token.is("{") else { return [token] }
            var depth = 1
            var group: [Token] = []
            while let next = peek {
                index += 1
                if next.is("{") { depth += 1 }
                if next.is("}") {
                    depth -= 1
                    if depth == 0 { return group }
                }
                group.append(next)
            }
            return group
        }

        /// A bracketed optional argument, if present.
        private mutating func readOptional() -> [Token]? {
            guard let start = nextNonSpace(from: index), tokens[start].is("[") else { return nil }
            var i = start + 1
            var depth = 0
            var group: [Token] = []
            while i < tokens.count {
                let token = tokens[i]
                if token.is("{") { depth += 1 }
                if token.is("}") { depth -= 1 }
                if depth == 0, token.is("]") { index = i + 1; return group }
                group.append(token)
                i += 1
            }
            return nil
        }

        private mutating func readStar() -> Bool {
            if peek?.is("*") == true { index += 1; return true }
            return false
        }

        private func plain(_ tokens: [Token]) -> String { tokens.map(\.latex).joined() }

        // MARK: Steps

        private mutating func step() {
            let token = tokens[index]
            index += 1
            switch token {
            case .character(let c):
                character(c)
            case .command(let name):
                command(name)
            }
        }

        private mutating func character(_ c: Character) {
            if !textMode, c == "'" || c == "\u{2032}" || c == "\u{2033}" || c == "\u{2034}" || c == "\u{2019}" {
                primes(first: c)
                return
            }
            if c == "~" { emit(textMode ? " " : "\\ "); return }
            if let script = Self.superscripts[c] ?? Self.subscripts[c] {
                // A run like x⁻¹ becomes one script, x^{-1}.
                let table = Self.superscripts[c] != nil ? Self.superscripts : Self.subscripts
                var text = script
                while let token = peek, case .character(let next) = token, let more = table[next] {
                    text += more
                    index += 1
                }
                emit((table == Self.superscripts ? "^{" : "_{") + text + "}")
                return
            }
            if let replacement = Self.unicode[c] {
                if textMode, let text = Self.unicodeText[c] { emit(text); return }
                emit(replacement)
                return
            }
            emit(String(c))
        }

        /// `f''` becomes `f\prime\prime`. The math font's prime is already raised, so it stays on
        /// the baseline rather than in a superscript, where it would be tiny and detached.
        private mutating func primes(first: Character) {
            func count(_ c: Character) -> Int {
                switch c {
                case "\u{2033}": 2
                case "\u{2034}": 3
                default: 1
                }
            }
            var total = count(first)
            while let token = peek, case .character(let c) = token,
                  c == "'" || c == "\u{2032}" || c == "\u{2033}" || c == "\u{2034}" || c == "\u{2019}" {
                total += count(c)
                index += 1
            }
            emit(String(repeating: "\\prime", count: total))
        }

        private mutating func command(_ name: String) {
            if let handler = Self.handlers[name] {
                handler(&self, name)
            } else if let renamed = Self.renamed[name] {
                emit(renamed)
            } else if name == "begin" {
                environment()
            } else {
                emit(command: name)
            }
        }

        // MARK: Handlers

        typealias Handler = (inout Rewriter, String) -> Void

        static let renamed: [String: String] = [
            "lvert": "|", "rvert": "|", "lVert": "\\|", "rVert": "\\|", "lbrack": "[", "rbrack": "]",
            "mathscr": "\\mathcal", "mathds": "\\mathbb", "mathbbm": "\\mathbb", "Bbb": "\\mathbb",
            "boldsymbol": "\\bm", "pmb": "\\bm", "it": "\\mathit", "sf": "\\mathsf", "tt": "\\mathtt",
            "mathup": "\\mathrm", "mathbold": "\\mathbf", ":": "\\>", "&": "\\And", "thinspace": "\\,",
            "medspace": "\\>", "thickspace": "\\;", "negthinspace": "\\!", "enspace": "\\;", "enskip": "\\;",
            "space": "\\ ", "nobreakspace": "\\ ", "overbar": "\\overline", "widebar": "\\overline",
            "widecheck": "\\check", "restriction": "\\upharpoonright", "thicksim": "\\sim",
            "thickapprox": "\\approx", "varpropto": "\\propto", "shortmid": "\\mid", "shortparallel": "\\parallel",
            "nshortmid": "\\nmid", "nshortparallel": "\\nparallel", "owns": "\\ni", "centerdot": "\\cdot",
            "bigtriangleup": "\\triangle", "vartriangle": "\\triangle", "intop": "\\int", "smallint": "\\int",
            "hslash": "\\hbar", "ldotp": ".",
        ]

        static let handlers: [String: Handler] = {
            var table: [String: Handler] = [:]
            for name in ["nonumber", "notag", "nobreak", "allowbreak", "displaylimits", "-", "/", "protect",
                         "leavevmode", "noindent", "hline", "hdashline", "toprule", "midrule", "bottomrule",
                         "centering", "strut", "mathstrut", "relax"] {
                table[name] = { _, _ in }
            }
            for name in ["label", "phantom", "hphantom", "vphantom", "vspace", "cline", "eqref", "ref"] {
                table[name] = { r, name in
                    if name == "vspace" { _ = r.readStar() }
                    _ = r.readArgument()
                    if name == "eqref" || name == "ref" { r.emit("(\\text{ref})") }
                }
            }
            table["hspace"] = { r, _ in _ = r.readStar(); _ = r.readArgument(); r.emit("\\quad") }
            for name in ["kern", "mkern", "hskip", "mskip"] { table[name] = { r, _ in r.skipDimension(); r.emit("\\,") } }
            table["tag"] = { r, _ in
                let starred = r.readStar()
                guard let label = r.readArgument() else { return }
                let text = r.rewritten(label, textMode: true)
                r.emit(starred ? "\\qquad\\text{\(text)}" : "\\qquad\\text{(\(text))}")
            }
            for name in ["intertext", "shortintertext"] {
                table[name] = { r, _ in
                    guard let text = r.readArgument() else { return }
                    r.emit("\\text{" + r.rewritten(text, textMode: true) + "}")
                }
            }
            table["\\"] = { r, _ in
                // Row breaks accept a star and a spacing argument SwiftMath doesn't parse.
                r.skipRowSpacing()
                r.emit("\\\\")
            }
            for (name, style, binomial) in [("dfrac", "displaystyle", false), ("cfrac", "displaystyle", false),
                                            ("tfrac", "textstyle", false), ("dbinom", "displaystyle", true),
                                            ("tbinom", "textstyle", true)] {
                table[name] = { r, name in
                    if name == "cfrac" { _ = r.readOptional() }
                    let numerator = r.readArgument() ?? []
                    let denominator = r.readArgument() ?? []
                    // An empty-delimited group scopes the style change to this fraction.
                    r.emit("\\left.\\\(style)\\\(binomial ? "binom" : "frac"){\(r.rewritten(numerator))}{\(r.rewritten(denominator))}\\right.")
                }
            }
            table["operatorname"] = { r, _ in
                let limits = r.readStar()
                let argument = r.readArgument() ?? []
                if let nucleus = Self.operatorText(argument) {
                    r.emit(command: LaTeXCompatibility.operatorCommand(nucleus: nucleus, limits: limits))
                } else {
                    r.emit("\\mathrm{" + r.rewritten(argument) + "}")
                }
            }
            for name in ["mathop", "mathbin", "mathrel", "mathord", "mathopen", "mathclose", "mathpunct", "mathinner"] {
                table[name] = { r, name in
                    let argument = r.readArgument() ?? []
                    if name == "mathop", let nucleus = Self.operatorText(argument) {
                        r.emit(command: LaTeXCompatibility.operatorCommand(nucleus: nucleus, limits: true))
                        return
                    }
                    r.emit("{" + r.rewritten(argument) + "}")
                    // \limits needs an operator, which the group no longer is.
                    if let next = r.nextNonSpace(from: r.index),
                       r.tokens[next].is(command: "limits") || r.tokens[next].is(command: "nolimits") {
                        r.index = next + 1
                    }
                }
            }
            for size in ["big", "Big", "bigg", "Bigg"] {
                for suffix in ["", "l", "r", "m"] {
                    table[size + suffix] = { r, _ in r.dropSizedDelimiter() }
                }
            }
            table["middle"] = { r, _ in r.dropSizedDelimiter() }
            table["not"] = { r, _ in r.negation() }
            table["pmod"] = { r, _ in
                let argument = r.rewritten(r.readArgument() ?? [])
                r.emit((r.display ? "\\quad" : "\\>\\>") + "(\\mathrm{mod}\\;" + argument + ")")
            }
            table["pod"] = { r, _ in
                let argument = r.rewritten(r.readArgument() ?? [])
                r.emit((r.display ? "\\quad" : "\\>\\>") + "(" + argument + ")")
            }
            table["mod"] = { r, _ in
                let argument = r.rewritten(r.readArgument() ?? [])
                r.emit((r.display ? "\\quad" : "\\>\\>\\>") + "\\mathrm{mod}\\,\\," + argument)
            }
            table["bmod"] = { r, _ in r.emit("\\;\\mathrm{mod}\\;") }
            for name in ["overset", "underset", "stackrel"] {
                table[name] = { r, name in
                    let annotation = r.rewritten(r.readArgument() ?? [])
                    let base = r.rewritten(r.readArgument() ?? [])
                    r.emit(r.stacked(base: base, annotation: annotation, above: name != "underset"))
                }
            }
            let arrows: [String: String] = [
                "xrightarrow": "\u{27F6}", "xleftarrow": "\u{27F5}", "xRightarrow": "\u{27F9}",
                "xLeftarrow": "\u{27F8}", "xleftrightarrow": "\u{27F7}", "xLeftrightarrow": "\u{27FA}",
                "xmapsto": "\u{27FC}", "xhookrightarrow": "\u{21AA}", "xhookleftarrow": "\u{21A9}",
                "xrightharpoonup": "\u{21C0}", "xrightleftharpoons": "\u{21CC}", "xlongequal": "=",
            ]
            for (name, arrow) in arrows {
                table[name] = { r, _ in
                    let below = r.readOptional().map { r.rewritten($0) } ?? ""
                    let above = r.rewritten(r.readArgument() ?? [])
                    var result = "\\" + LaTeXCompatibility.operatorCommand(nucleus: arrow, limits: true)
                    if !above.isEmpty { result += "^{" + above + "}" }
                    if !below.isEmpty { result += "_{" + below + "}" }
                    r.emit(result)
                }
            }
            for (name, line) in [("underbrace", "underline"), ("underbracket", "underline"),
                                 ("overbrace", "overline"), ("overbracket", "overline")] {
                table[name] = { r, _ in
                    r.emit("\\" + line + "{" + r.rewritten(r.readArgument() ?? []) + "}")
                }
            }
            for name in ["boxed", "fbox", "framebox"] {
                table[name] = { r, name in
                    _ = r.readOptional()
                    let argument = r.readArgument() ?? []
                    let body = name == "boxed" ? r.rewritten(argument) : "\\text{" + r.rewritten(argument, textMode: true) + "}"
                    r.emit("\\overline{\\underline{" + body + "}}")
                }
            }
            for name in ["cancel", "bcancel", "xcancel", "sout"] {
                table[name] = { r, _ in r.emit("\\color{#8E8E93}{" + r.rewritten(r.readArgument() ?? []) + "}") }
            }
            table["cancelto"] = { r, _ in
                let target = r.rewritten(r.readArgument() ?? [])
                let body = r.rewritten(r.readArgument() ?? [])
                r.emit("\\left.\\color{#8E8E93}{" + body + "}\\right.^{" + target + "}")
            }
            table["overrightarrow"] = { r, _ in r.emit("\\vec{" + r.rewritten(r.readArgument() ?? []) + "}") }
            for (name, arrow, above) in [("overleftarrow", "\\leftarrow", true), ("overleftrightarrow", "\\leftrightarrow", true),
                                         ("underrightarrow", "\\rightarrow", false), ("underleftarrow", "\\leftarrow", false),
                                         ("underleftrightarrow", "\\leftrightarrow", false)] {
                table[name] = { r, _ in
                    let base = r.rewritten(r.readArgument() ?? [])
                    r.emit("\\left." + base + "\\right." + (above ? "^{" : "_{") + arrow + "}")
                }
            }
            table["substack"] = { r, _ in
                let rows = Self.split(r.readArgument() ?? [], at: .command("\\")).map { r.rewritten($0) }
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                guard var result = rows.last else { return }
                for row in rows.dropLast().reversed() { result = "{" + row + " \\atop " + result + "}" }
                r.emit("{" + result + "}")
            }
            for name in ["color", "textcolor", "colorbox"] {
                table[name] = { r, name in
                    let color = r.plain(r.readArgument() ?? []).trimmingCharacters(in: .whitespaces)
                    if name != "color" || r.peekIsGroup {
                        let body = r.rewritten(r.readArgument() ?? [])
                        guard let hex = Self.color(color) else { r.emit("{" + body + "}"); return }
                        r.emit("\\\(name == "colorbox" ? "colorbox" : "color"){\(hex)}{\(body)}")
                    } else {
                        // `\color{red} x + y` colors the rest of the group.
                        let body = r.rewritten(r.readRestOfGroup())
                        guard let hex = Self.color(color) else { r.emit(body); return }
                        r.emit("\\color{\(hex)}{\(body)}")
                    }
                }
            }
            for name in ["text", "textrm", "textbf", "textit", "textsf", "texttt", "textup", "textnormal",
                         "textmd", "emph", "mbox", "hbox", "textsl", "textsc"] {
                table[name] = { r, name in
                    let argument = r.readArgument() ?? []
                    var body = r.rewritten(argument, textMode: true)
                    let target: String = switch name {
                    case "textbf": "textbf"
                    case "textit", "emph", "textsl": "textit"
                    case "textsf": "textsf"
                    case "texttt": "texttt"
                    default: "text"
                    }
                    // Only \text keeps spaces in SwiftMath; other text fonts need escaped spaces.
                    if target != "text" { body = body.replacingOccurrences(of: " ", with: "\\ ") }
                    r.emit("\\" + target + "{" + body + "}")
                }
            }
            table["end"] = { r, _ in
                // A stray \end without a matching \begin is left for SwiftMath to report.
                r.emit(command: "end")
            }
            return table
        }()

        private var peekIsGroup: Bool {
            guard let next = nextNonSpace(from: index) else { return false }
            return tokens[next].is("{")
        }

        /// Tokens up to the end of the enclosing group, cell or row.
        private mutating func readRestOfGroup() -> [Token] {
            var depth = 0
            var rest: [Token] = []
            while let token = peek {
                if token.is("{") { depth += 1 }
                if token.is("}") {
                    if depth == 0 { break }
                    depth -= 1
                }
                if depth == 0, token.is("&") || token.is(command: "\\") { break }
                rest.append(token)
                index += 1
            }
            return rest
        }

        /// Drops the `*` and `[4pt]` that may follow a row break.
        fileprivate mutating func skipRowSpacing() {
            _ = readStar()
            let saved = index
            if let spacing = readOptional(), !Self.isDimension(spacing) { index = saved }
        }

        static func isDimension(_ tokens: [Token]) -> Bool {
            let text = tokens.map(\.latex).joined().trimmingCharacters(in: .whitespaces)
            return text.range(of: #"^[-+]?[0-9]*\.?[0-9]+\s*(pt|em|ex|mm|cm|in|mu|bp|pc|sp|dd|cc)$"#, options: .regularExpression) != nil
        }

        private mutating func skipDimension() {
            skipSpaces()
            while let token = peek, case .character(let c) = token, c.isNumber || c == "." || c == "-" || c == "+" { index += 1 }
            skipSpaces()
            var unit = 0
            while unit < 2, let token = peek, case .character(let c) = token, c.isASCIILetter { index += 1; unit += 1 }
        }

        /// `\big(` keeps the delimiter at its normal size; `\big.` disappears.
        private mutating func dropSizedDelimiter() {
            guard let next = nextNonSpace(from: index) else { return }
            if tokens[next].is(".") { index = next + 1 }
        }

        private mutating func negation() {
            guard let next = nextNonSpace(from: index) else { emit(command: "not"); return }
            let token = tokens[next]
            let key: String
            switch token {
            case .character(let c): key = String(c)
            case .command(let name): key = "\\" + name
            }
            if let negated = Self.negations[key] {
                index = next + 1
                emit(negated)
            } else {
                emit(command: "not")
            }
        }

        static let negations: [String: String] = [
            "=": "\\neq", "<": "\\nless", ">": "\\ngtr", "\\in": "\\notin", "\\ni": "\\nni", "\\equiv": "\\nequiv",
            "\\mid": "\\nmid", "\\parallel": "\\nparallel", "\\leq": "\\nleq", "\\le": "\\nleq", "\\geq": "\\ngeq",
            "\\ge": "\\ngeq", "\\leqslant": "\\nleq", "\\geqslant": "\\ngeq", "\\subset": "\\nsubset",
            "\\supset": "\\nsupset", "\\subseteq": "\\nsubseteq", "\\supseteq": "\\nsupseteq", "\\sim": "\\nsim",
            "\\simeq": "\\nsimeq", "\\cong": "\\ncong", "\\approx": "\\napprox", "\\asymp": "\\nasymp",
            "\\prec": "\\nprec", "\\succ": "\\nsucc", "\\vdash": "\\nvdash", "\\models": "\\nvDash",
            "\\vDash": "\\nvDash", "\\exists": "\\nexists", "\\rightarrow": "\\nrightarrow", "\\to": "\\nrightarrow",
            "\\leftarrow": "\\nleftarrow", "\\Rightarrow": "\\nRightarrow", "\\Leftarrow": "\\nLeftarrow",
            "\\leftrightarrow": "\\nleftrightarrow", "\\Leftrightarrow": "\\nLeftrightarrow", "\\neq": "=",
            "\\ne": "=", "|": "\\nmid", "\\|": "\\nparallel",
        ]

        /// Upright operator text for `\operatorname`: letters, digits and simple spacing only.
        static func operatorText(_ tokens: [Token]) -> String? {
            var text = ""
            for token in tokens {
                switch token {
                case .character(let c) where c.isLetter || c.isNumber || c == "-" || c == "'" || c == "*" || c == "/":
                    text.append(c)
                case .character(" "):
                    continue
                case .command(","), .command(";"), .command(">"), .command(":"), .command(" "), .command("!"):
                    text.append("\u{2009}")
                case .command(let name) where Self.operatorWords.contains(name):
                    if !text.isEmpty && !text.hasSuffix("\u{2009}") { text.append("\u{2009}") }
                    text += name
                default:
                    return nil
                }
            }
            return text.isEmpty ? nil : text
        }

        private static let operatorWords: Set<String> = ["arg", "max", "min", "sup", "inf", "lim", "log", "det", "exp", "sin", "cos", "tan"]

        /// `\overset{a}{=}`: a symbol base becomes an operator with limits, so the annotation sits
        /// above it in display math. Other bases get the annotation as a script on a group.
        private func stacked(base: String, annotation: String, above: Bool) -> String {
            let script = (above ? "^{" : "_{") + annotation + "}"
            if let list = MTMathListBuilder.build(fromString: base), !list.atoms.isEmpty,
               list.atoms.allSatisfy({ $0.superScript == nil && $0.subScript == nil }) {
                let atoms = list.atoms
                if atoms.count == 1, atoms[0] is MTLargeOperator {
                    return base + "\\limits" + script
                }
                let symbolTypes: [MTMathAtomType] = [.relation, .binaryOperator, .ordinary, .open, .close, .punctuation]
                if atoms.count == 1, symbolTypes.contains(atoms[0].type), !atoms[0].nucleus.isEmpty,
                   !atoms[0].nucleus.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) && $0.isASCII }) {
                    return "\\" + LaTeXCompatibility.operatorCommand(nucleus: atoms[0].nucleus, limits: true) + script
                }
                if atoms.allSatisfy({ $0.type == .largeOperator && $0.nucleus.count > 1 }) {
                    let nucleus = atoms.map(\.nucleus).joined(separator: "\u{2009}")
                    return "\\" + LaTeXCompatibility.operatorCommand(nucleus: nucleus, limits: true) + script
                }
            }
            return "\\left." + base + "\\right." + script
        }

        static func color(_ name: String) -> String? {
            let value = name.lowercased()
            if value.hasPrefix("#"), value.count == 7 { return value.uppercased() }
            if value.count == 6, value.allSatisfy(\.isHexDigit) { return "#" + value.uppercased() }
            return [
                "red": "#E5484D", "blue": "#3B82F6", "green": "#30A46C", "orange": "#F2811D", "purple": "#8E4EC6",
                "violet": "#8E4EC6", "magenta": "#D6409F", "cyan": "#05A2C2", "teal": "#12A594", "brown": "#AD7F58",
                "olive": "#868E2B", "pink": "#E93D82", "gray": "#8E8E93", "grey": "#8E8E93", "darkgray": "#6E6E73",
                "lightgray": "#AEAEB2", "yellow": "#D6A100", "lime": "#7CB342",
            ][value]
        }

        static func split(_ tokens: [Token], at separator: Token) -> [[Token]] {
            var parts: [[Token]] = [[]]
            var depth = 0
            var environments = 0
            var i = 0
            while i < tokens.count {
                let token = tokens[i]
                if token.is("{") { depth += 1 }
                if token.is("}") { depth -= 1 }
                if token.is(command: "begin") { environments += 1 }
                if token.is(command: "end") { environments -= 1 }
                if depth == 0, environments == 0, token == separator {
                    parts.append([])
                } else {
                    parts[parts.count - 1].append(token)
                }
                i += 1
            }
            return parts
        }

        // MARK: Environments

        private mutating func readEnvironmentName() -> String? {
            skipSpaces()
            guard peek?.is("{") == true else { return nil }
            var i = index + 1
            var name = ""
            while i < tokens.count, case .character(let c) = tokens[i], c != "}" { name.append(c); i += 1 }
            guard i < tokens.count, tokens[i].is("}") else { return nil }
            index = i + 1
            return name.trimmingCharacters(in: .whitespaces)
        }

        /// Tokens up to the matching `\end{name}`, which is consumed.
        private mutating func readEnvironmentBody(_ name: String) -> [Token]? {
            var depth = 0
            var body: [Token] = []
            while index < tokens.count {
                let token = tokens[index]
                if token.is(command: "begin") || token.is(command: "end") {
                    let start = index
                    index += 1
                    let nested = readEnvironmentName()
                    if token.is(command: "begin") {
                        depth += 1
                    } else if depth == 0 {
                        if nested == name { return body }
                    } else {
                        depth -= 1
                    }
                    body += tokens[start..<index]
                    continue
                }
                body.append(token)
                index += 1
            }
            return nil
        }

        private mutating func environment() {
            let start = index
            guard let name = readEnvironmentName() else { emit(command: "begin"); return }
            let kind = Self.environmentKind(name)
            if kind == .unknown {
                // Unknown environments are passed through for SwiftMath to report.
                emit("\\begin{" + name + "}")
                return
            }
            // Placement options and column specs aren't supported, so they're dropped.
            if name.hasSuffix("matrix*") || ["aligned", "gathered", "alignedat", "array", "subarray"].contains(name) {
                _ = readOptional()
            }
            if kind == .array || ["alignat", "alignat*", "alignedat", "xalignat"].contains(name) {
                _ = readArgument()
            }
            guard let body = readEnvironmentBody(name) else {
                index = start
                emit("\\begin")
                return
            }
            emit(environment(kind, name: name, body: body))
        }

        enum EnvironmentKind { case plain, aligned, eqnarray, gather, cases, rcases, matrix, array, unknown }

        static func environmentKind(_ name: String) -> EnvironmentKind {
            switch name {
            case "equation", "equation*", "displaymath", "math": .plain
            case "align", "align*", "aligned", "flalign", "flalign*", "alignat", "alignat*", "alignedat",
                 "split", "xalignat", "eqalign": .aligned
            case "eqnarray", "eqnarray*": .eqnarray
            case "gather", "gather*", "gathered", "multline", "multline*", "displaylines": .gather
            case "cases", "cases*", "dcases", "dcases*": .cases
            case "rcases", "rcases*", "drcases": .rcases
            case "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "matrix*", "pmatrix*", "bmatrix*",
                 "Bmatrix*", "vmatrix*", "Vmatrix*", "smallmatrix", "psmallmatrix", "bsmallmatrix", "Bsmallmatrix",
                 "vsmallmatrix", "Vsmallmatrix": .matrix
            case "array", "subarray", "tabular": .array
            default: .unknown
            }
        }

        private func rows(_ body: [Token]) -> [[String]] {
            var rows = Self.split(body, at: .command("\\")).enumerated().map { offset, row -> [Token] in
                guard offset > 0 else { return row }
                var spacing = Rewriter(tokens: row, display: display)
                spacing.skipRowSpacing()
                return Array(row[spacing.index...])
            }.map { row in
                Self.split(row, at: .character("&")).map { rewritten($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            }
            // A trailing \\ would add an empty row.
            while let last = rows.last, last.allSatisfy(\.isEmpty), rows.count > 1 { rows.removeLast() }
            return rows
        }

        private func environment(_ kind: EnvironmentKind, name: String, body: [Token]) -> String {
            func join(_ rows: [[String]]) -> String { rows.map { $0.joined(separator: " & ") }.joined(separator: " \\\\ ") }
            switch kind {
            case .plain:
                return rewritten(body)
            case .aligned:
                let rows = rows(body)
                let columns = rows.map(\.count).max() ?? 1
                let fitted: [[String]] = rows.map { row in
                    // SwiftMath's aligned has exactly two columns: right- then left-aligned.
                    if columns == 1 { return [row[0], ""] }
                    var cells = Array(row.prefix(2))
                    if cells.count < 2 { cells.append("") }
                    for (offset, cell) in row.dropFirst(2).enumerated() {
                        if offset.isMultiple(of: 2) { cells[1] += " \\qquad " }
                        cells[1] += cell
                    }
                    return cells
                }
                return "\\begin{aligned}" + join(fitted) + "\\end{aligned}"
            case .eqnarray:
                let fitted = rows(body).map { row -> [String] in
                    guard row.count > 1 else { return [row[0], ""] }
                    return [row[0], row.dropFirst().joined(separator: " ")]
                }
                return "\\begin{aligned}" + join(fitted) + "\\end{aligned}"
            case .gather:
                let rows = rows(body).map { [$0.filter { !$0.isEmpty }.joined(separator: " \\quad ")] }
                return "\\begin{gather}" + join(rows) + "\\end{gather}"
            case .cases, .rcases:
                let fitted = rows(body).map { row -> [String] in
                    var cells = Array(row.prefix(2))
                    if cells.count < 2 { cells.append("") }
                    for cell in row.dropFirst(2) where !cell.isEmpty { cells[1] += " \\quad " + cell }
                    return cells
                }
                if kind == .cases { return "\\begin{cases}" + join(fitted) + "\\end{cases}" }
                return "\\left.\\begin{matrix}" + join(fitted) + "\\end{matrix}\\right\\}"
            case .matrix:
                var base = name.replacingOccurrences(of: "*", with: "")
                if base.hasSuffix("smallmatrix") { base = base == "smallmatrix" ? "matrix" : String(base.dropLast("smallmatrix".count)) + "matrix" }
                return "\\begin{\(base)}" + join(rows(body)) + "\\end{\(base)}"
            case .array:
                return "\\begin{matrix}" + join(rows(body)) + "\\end{matrix}"
            case .unknown:
                return "\\begin{\(name)}" + plain(body) + "\\end{\(name)}"
            }
        }

        // MARK: Unicode

        /// Unicode math that SwiftMath would silently drop, mapped to commands it renders.
        static let unicode: [Character: String] = {
            var table: [Character: String] = [
                "\u{2212}": "-", "\u{2013}": "-", "\u{2014}": "-", "\u{00B7}": "\\cdot", "\u{22C5}": "\\cdot",
                "\u{00D7}": "\\times", "\u{00F7}": "\\div", "\u{00B1}": "\\pm", "\u{2213}": "\\mp", "\u{221E}": "\\infty",
                "\u{2248}": "\\approx", "\u{2260}": "\\neq", "\u{2261}": "\\equiv", "\u{2262}": "\\nequiv",
                "\u{2264}": "\\leq", "\u{2265}": "\\geq", "\u{2A7D}": "\\leqslant", "\u{2A7E}": "\\geqslant",
                "\u{226A}": "\\ll", "\u{226B}": "\\gg", "\u{221D}": "\\propto", "\u{2192}": "\\rightarrow",
                "\u{2190}": "\\leftarrow", "\u{2194}": "\\leftrightarrow", "\u{21D2}": "\\Rightarrow",
                "\u{21D0}": "\\Leftarrow", "\u{21D4}": "\\Leftrightarrow", "\u{27F9}": "\\implies", "\u{27F8}": "\\impliedby",
                "\u{27FA}": "\\iff", "\u{21A6}": "\\mapsto", "\u{27F6}": "\\longrightarrow", "\u{27F5}": "\\longleftarrow",
                "\u{2191}": "\\uparrow", "\u{2193}": "\\downarrow", "\u{2208}": "\\in", "\u{2209}": "\\notin",
                "\u{220B}": "\\ni", "\u{2282}": "\\subset", "\u{2283}": "\\supset", "\u{2286}": "\\subseteq",
                "\u{2287}": "\\supseteq", "\u{228A}": "\\subsetneq", "\u{228B}": "\\supsetneq", "\u{222A}": "\\cup",
                "\u{2229}": "\\cap", "\u{2205}": "\\emptyset", "\u{2200}": "\\forall", "\u{2203}": "\\exists",
                "\u{2204}": "\\nexists", "\u{00AC}": "\\neg", "\u{2227}": "\\wedge", "\u{2228}": "\\vee",
                "\u{2295}": "\\oplus", "\u{2297}": "\\otimes", "\u{2299}": "\\odot", "\u{2202}": "\\partial",
                "\u{2207}": "\\nabla", "\u{2211}": "\\sum", "\u{220F}": "\\prod", "\u{222B}": "\\int",
                "\u{222C}": "\\iint", "\u{222D}": "\\iiint", "\u{222E}": "\\oint", "\u{221A}": "\\surd",
                "\u{2218}": "\\circ", "\u{2219}": "\\bullet", "\u{2022}": "\\bullet", "\u{00B0}": "\\degree",
                "\u{2026}": "\\ldots", "\u{22EF}": "\\cdots", "\u{22EE}": "\\vdots", "\u{22F1}": "\\ddots",
                "\u{223C}": "\\sim", "\u{2245}": "\\cong", "\u{2243}": "\\simeq", "\u{22A5}": "\\perp",
                "\u{27C2}": "\\perp", "\u{2225}": "\\parallel", "\u{2223}": "\\mid", "\u{2224}": "\\nmid",
                "\u{27E8}": "\\langle", "\u{27E9}": "\\rangle", "\u{2329}": "\\langle", "\u{232A}": "\\rangle",
                "\u{230A}": "\\lfloor", "\u{230B}": "\\rfloor", "\u{2308}": "\\lceil", "\u{2309}": "\\rceil",
                "\u{2016}": "\\|", "\u{2113}": "\\ell", "\u{210F}": "\\hbar", "\u{2135}": "\\aleph",
                "\u{2220}": "\\angle", "\u{25B3}": "\\triangle", "\u{2234}": "\\therefore", "\u{2235}": "\\because",
                "\u{22A2}": "\\vdash", "\u{22A8}": "\\models", "\u{2216}": "\\setminus", "\u{2032}": "\\prime",
                "\u{2124}": "\\mathbb{Z}", "\u{211D}": "\\mathbb{R}", "\u{2115}": "\\mathbb{N}", "\u{211A}": "\\mathbb{Q}",
                "\u{2102}": "\\mathbb{C}", "\u{2119}": "\\mathbb{P}", "\u{1D53C}": "\\mathbb{E}", "\u{2254}": "\\coloneqq",
                "\u{225C}": "\\triangleq", "\u{2272}": "\\lesssim", "\u{2273}": "\\gtrsim", "\u{227A}": "\\prec",
                "\u{227B}": "\\succ", "\u{2AAF}": "\\preceq", "\u{2AB0}": "\\succeq", "\u{21AA}": "\\hookrightarrow",
                "\u{21CC}": "\\rightleftharpoons", "\u{25A1}": "\\Box", "\u{25A0}": "\\blacksquare", "\u{2713}": "\\checkmark",
                "\u{00A0}": "\\ ", "\u{2009}": "\\,", "\u{202F}": "\\,", "\u{2003}": "\\quad", "\u{2002}": "\\;",
                "\u{201C}": "\"", "\u{201D}": "\"", "\u{2018}": "`",
            ]
            let lower = ["alpha", "beta", "gamma", "delta", "varepsilon", "zeta", "eta", "theta", "iota", "kappa", "lambda",
                         "mu", "nu", "xi", "o", "pi", "rho", "varsigma", "sigma", "tau", "upsilon", "varphi", "chi", "psi", "omega"]
            for (offset, name) in lower.enumerated() {
                let scalar = UnicodeScalar(0x03B1 + offset)!
                table[Character(scalar)] = name == "o" ? "o" : "\\" + name
            }
            let upper: [UInt32: String] = [0x0393: "Gamma", 0x0394: "Delta", 0x0398: "Theta", 0x039B: "Lambda", 0x039E: "Xi",
                                           0x03A0: "Pi", 0x03A3: "Sigma", 0x03A5: "Upsilon", 0x03A6: "Phi", 0x03A8: "Psi", 0x03A9: "Omega"]
            for (value, name) in upper { table[Character(UnicodeScalar(value)!)] = "\\" + name }
            let latinLookalikes: [UInt32: String] = [0x0391: "A", 0x0392: "B", 0x0395: "E", 0x0396: "Z", 0x0397: "H", 0x0399: "I",
                                                     0x039A: "K", 0x039C: "M", 0x039D: "N", 0x039F: "O", 0x03A1: "P", 0x03A4: "T", 0x03A7: "X"]
            for (value, letter) in latinLookalikes { table[Character(UnicodeScalar(value)!)] = letter }
            table["\u{03F5}"] = "\\epsilon"
            table["\u{03D5}"] = "\\phi"
            table["\u{03D1}"] = "\\vartheta"
            table["\u{03F1}"] = "\\varrho"
            table["\u{03D6}"] = "\\varpi"
            table["\u{03F0}"] = "\\varkappa"
            return table
        }()

        static let superscripts: [Character: String] = [
            "\u{00B2}": "2", "\u{00B3}": "3", "\u{00B9}": "1", "\u{2070}": "0", "\u{2074}": "4", "\u{2075}": "5",
            "\u{2076}": "6", "\u{2077}": "7", "\u{2078}": "8", "\u{2079}": "9", "\u{207A}": "+", "\u{207B}": "-",
            "\u{207C}": "=", "\u{207D}": "(", "\u{207E}": ")", "\u{207F}": "n", "\u{2071}": "i", "\u{1D40}": "T",
            "\u{1D57}": "t", "\u{1D4F}": "k", "\u{02B2}": "j", "\u{02E3}": "x", "\u{02B8}": "y", "\u{1D50}": "m",
        ]

        static let subscripts: [Character: String] = [
            "\u{2080}": "0", "\u{2081}": "1", "\u{2082}": "2", "\u{2083}": "3", "\u{2084}": "4", "\u{2085}": "5",
            "\u{2086}": "6", "\u{2087}": "7", "\u{2088}": "8", "\u{2089}": "9", "\u{208A}": "+", "\u{208B}": "-",
            "\u{208C}": "=", "\u{208D}": "(", "\u{208E}": ")", "\u{1D62}": "i", "\u{2C7C}": "j", "\u{2099}": "n",
            "\u{2096}": "k", "\u{2098}": "m", "\u{2093}": "x", "\u{2090}": "a", "\u{2091}": "e", "\u{2092}": "o",
            "\u{209C}": "t", "\u{209A}": "p", "\u{209B}": "s", "\u{2097}": "l", "\u{2095}": "h",
        ]

        /// Text-mode equivalents where the math replacement would be wrong inside `\text{}`.
        static let unicodeText: [Character: String] = [
            "\u{2212}": "-", "\u{2013}": "-", "\u{2014}": "-", "\u{00A0}": " ", "\u{2009}": " ", "\u{202F}": " ",
            "\u{2003}": " ", "\u{2002}": " ", "\u{2019}": "'", "\u{2018}": "'", "\u{201C}": "\"", "\u{201D}": "\"",
            "\u{2026}": "...",
        ]
    }
}

private extension Character {
    var isASCIILetter: Bool { isASCII && isLetter }
}
