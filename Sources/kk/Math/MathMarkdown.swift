import Foundation

/// Finds math in Markdown the way MarkdownView does, so it can be made renderable, checked,
/// and repaired. Code spans and fenced code blocks are skipped.
@MainActor
enum MathMarkdown {
    struct Segment: Equatable {
        /// The whole segment, delimiters included.
        let range: Range<String.Index>
        /// The LaTeX between the delimiters; for a bare environment, the whole environment.
        let bodyRange: Range<String.Index>
        let open: String
        let close: String
        let display: Bool
        /// A `\begin{…}…\end{…}` written without math delimiters. It's wrapped in `$$` when
        /// rendered, since MarkdownView recognizes only some environments on their own.
        let bare: Bool
    }

    struct Failure: Equatable {
        /// The segment as written, delimiters included. Identifies it for repair status.
        let source: String
        let body: String
        let display: Bool
        let error: String
    }

    /// The fenced-code language used to show a display equation that still can't render.
    static let failureLanguage = "kk-math"

    /// Identifies an equation across its Markdown and its code-block display, which drops
    /// list indentation.
    static func key(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Rendering

    private struct Rendered {
        let latex: String
        let error: String?
    }

    private static var cache: [String: Rendered] = [:]

    /// The body made compatible with SwiftMath, and its remaining parse error if any.
    private static func render(_ body: String, display: Bool) -> Rendered {
        let cacheKey = (display ? "d" : "i") + body
        if let cached = cache[cacheKey] { return cached }
        let latex = LaTeXCompatibility.equation(body, display: display)
        let rendered = Rendered(latex: latex, error: LaTeXCompatibility.error(in: latex))
        if cache.count > 2_000 { cache.removeAll() }
        cache[cacheKey] = rendered
        return rendered
    }

    /// Markdown for display: math rewritten for SwiftMath, and math that still can't render shown
    /// as its source (a code block for display math on its own lines, inline code otherwise)
    /// instead of disappearing.
    static func renderable(_ markdown: String) -> String {
        let segments = segments(in: markdown)
        guard !segments.isEmpty else { return markdown }
        var output = ""
        var cursor = markdown.startIndex
        for segment in segments {
            output += markdown[cursor..<segment.range.lowerBound]
            output += replacement(for: segment, in: markdown)
            cursor = segment.range.upperBound
        }
        output += markdown[cursor...]
        return output
    }

    private static func replacement(for segment: Segment, in markdown: String) -> String {
        let source = String(markdown[segment.range])
        let body = String(markdown[segment.bodyRange])
        let rendered = render(body, display: segment.display)
        guard rendered.error != nil else {
            var latex = rendered.latex
            if !segment.display {
                // Inline math must stay on one line without edge spaces to remain math.
                latex = latex.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
            }
            if segment.bare { return "$$" + latex + "$$" }
            return segment.open + latex + segment.close
        }
        if segment.display, let block = codeBlock(source, replacing: segment.range, in: markdown) { return block }
        return inlineCode(source)
    }

    /// A fenced block in place of display math that fills its lines, keeping list indentation.
    private static func codeBlock(_ source: String, replacing range: Range<String.Index>, in markdown: String) -> String? {
        let lineStart = markdown[..<range.lowerBound].lastIndex(of: "\n").map { markdown.index(after: $0) } ?? markdown.startIndex
        let prefix = markdown[lineStart..<range.lowerBound]
        let lineEnd = markdown[range.upperBound...].firstIndex(of: "\n") ?? markdown.endIndex
        guard prefix.allSatisfy({ $0 == " " }), prefix.count < 4,
              markdown[range.upperBound..<lineEnd].allSatisfy(\.isWhitespace) else { return nil }
        let fence = String(repeating: "`", count: max(3, longestRun(of: "`", in: source) + 1))
        let indent = String(prefix)
        let lines = source.components(separatedBy: "\n").map { line in
            line.hasPrefix(indent) ? String(line.dropFirst(indent.count)) : line.drop(while: { $0 == " " }).description
        }
        // The first line's indent is already in the output before this segment.
        return fence + failureLanguage + "\n" + lines.map { indent + $0 }.joined(separator: "\n") + "\n" + indent + fence
    }

    private static func inlineCode(_ source: String) -> String {
        let text = source.replacingOccurrences(of: "\n", with: " ")
        let fence = String(repeating: "`", count: longestRun(of: "`", in: text) + 1)
        let pad = text.hasPrefix("`") || text.hasSuffix("`") ? " " : ""
        return fence + pad + text + pad + fence
    }

    private static func longestRun(of character: Character, in text: String) -> Int {
        var longest = 0
        var current = 0
        for c in text {
            current = c == character ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }

    // MARK: - Checking and repair

    /// Math that still fails to render after compatibility rewriting, in order, without repeats.
    static func failures(in markdown: String) -> [Failure] {
        var seen = Set<String>()
        var result: [Failure] = []
        for segment in segments(in: markdown) {
            let source = String(markdown[segment.range])
            let body = String(markdown[segment.bodyRange])
            guard let error = render(body, display: segment.display).error,
                  seen.insert(key(source)).inserted else { continue }
            result.append(Failure(source: source, body: body, display: segment.display, error: error))
        }
        return result
    }

    /// Whether `latex` renders as math in the given context.
    static func renders(_ latex: String, display: Bool) -> Bool {
        render(latex, display: display).error == nil
    }

    /// Replaces the body of every segment written as `source`. Returns nil if none is found.
    static func replacing(_ source: String, withBody body: String, in markdown: String) -> String? {
        let matches = segments(in: markdown).filter { key(String(markdown[$0.range])) == key(source) }
        guard !matches.isEmpty else { return nil }
        var updated = markdown
        for segment in matches.reversed() {
            var latex = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if segment.display {
                if segment.bare {
                    updated.replaceSubrange(segment.range, with: "$$" + latex + "$$")
                } else {
                    // Keep the original layout, such as $$ on lines of their own.
                    let original = markdown[segment.bodyRange]
                    let leading = original.prefix(while: \.isWhitespace)
                    let trailing = original.dropFirst(leading.count).reversed().prefix(while: \.isWhitespace).reversed()
                    updated.replaceSubrange(segment.bodyRange, with: leading + latex + String(trailing))
                }
            } else {
                latex = latex.replacingOccurrences(of: "\n", with: " ")
                guard !latex.contains("$") || segment.open != "$" else { return nil }
                updated.replaceSubrange(segment.bodyRange, with: latex)
            }
        }
        return updated
    }

    /// LaTeX from a repair reply, without any math delimiters the model added.
    static func strippingDelimiters(_ latex: String) -> String {
        var text = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("$$", "$$"), ("\\[", "\\]"), ("\\(", "\\)"), ("$", "$")] {
            if text.hasPrefix(open), text.hasSuffix(close), text.count >= open.count + close.count {
                text = String(text.dropFirst(open.count).dropLast(close.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return text
    }

    // MARK: - Finding math

    /// Environments MarkdownView renders on their own, without `$$`.
    private static let recognizedEnvironments: Set<String> = [
        "equation", "equation*", "matrix", "pmatrix", "bmatrix", "Bmatrix", "vmatrix", "Vmatrix", "eqalign",
        "split", "aligned", "displaylines", "gather", "eqnarray", "cases",
    ]

    /// Display environments models write without `$$`; they're wrapped so they render.
    private static let bareEnvironments: Set<String> = [
        "align", "align*", "gather*", "multline", "multline*", "flalign", "flalign*", "alignat", "alignat*",
        "eqnarray*", "gathered", "alignedat", "dcases", "rcases", "array",
    ]

    static func segments(in markdown: String) -> [Segment] {
        var candidates: [Segment] = []
        for range in mathRanges(in: markdown) {
            candidates += delimited(in: markdown, range: range)
            candidates += environments(in: markdown, range: range)
        }
        // Like MarkdownView: earliest first, the longer of two at the same start, no overlaps.
        candidates.sort {
            $0.range.lowerBound != $1.range.lowerBound ? $0.range.lowerBound < $1.range.lowerBound : $0.range.upperBound > $1.range.upperBound
        }
        var result: [Segment] = []
        for candidate in candidates {
            if let last = result.last, last.range.overlaps(candidate.range) { continue }
            result.append(candidate)
        }
        return result
    }

    private static let delimitedExpression = try! NSRegularExpression(pattern: [
        #"(\$\$[\s\S]*?\$\$)"#,
        #"(\\\([\s\S]*?\\\))"#,
        #"(?:(?<=^)|(?<=\n))[ \t]*(\\\[[\s\S]*?\\\])"#,
        #"(\$(?!\s)([^\r\n$]+?)(?<!\s)\$(?!\d))"#,
    ].joined(separator: "|"))

    private static func delimited(in markdown: String, range: Range<String.Index>) -> [Segment] {
        var result: [Segment] = []
        let kinds: [(group: Int, open: String, close: String, display: Bool)] = [
            (1, "$$", "$$", true), (2, "\\(", "\\)", false), (3, "\\[", "\\]", true), (4, "$", "$", false),
        ]
        // Anchoring bounds make `^` match at the range start, as when MarkdownView matches a substring.
        delimitedExpression.enumerateMatches(in: markdown, range: NSRange(range, in: markdown)) { match, _, _ in
            guard let match else { return }
            for kind in kinds {
                guard let found = Range(match.range(at: kind.group), in: markdown) else { continue }
                let lower = found.lowerBound
                let upper = found.upperBound
                guard !isEscaped(markdown, lower), !isEscaped(markdown, markdown.index(upper, offsetBy: -kind.close.count)) else { break }
                if kind.group == 3 {
                    let lineStart = markdown[..<lower].lastIndex(of: "\n").map { markdown.index(after: $0) } ?? markdown.startIndex
                    guard markdown[lineStart..<lower].allSatisfy(\.isWhitespace) else { break }
                }
                let body = markdown.index(lower, offsetBy: kind.open.count)..<markdown.index(upper, offsetBy: -kind.close.count)
                result.append(Segment(range: lower..<upper, bodyRange: body, open: kind.open, close: kind.close,
                                      display: kind.display, bare: false))
                break
            }
        }
        return result
    }

    private static func environments(in markdown: String, range: Range<String.Index>) -> [Segment] {
        var result: [Segment] = []
        var index = range.lowerBound
        while index < range.upperBound {
            guard markdown[index] == "\\", !isEscaped(markdown, index),
                  let open = environmentToken(markdown, at: index, limit: range.upperBound), open.begin,
                  recognizedEnvironments.contains(open.name) || bareEnvironments.contains(open.name) else {
                index = markdown.index(after: index)
                continue
            }
            var names = [open.name]
            var cursor = open.range.upperBound
            var end: String.Index?
            while cursor < range.upperBound {
                if markdown[cursor] == "\\", !isEscaped(markdown, cursor), let token = environmentToken(markdown, at: cursor, limit: range.upperBound) {
                    if token.begin { names.append(token.name) }
                    else if names.last == token.name {
                        names.removeLast()
                        if names.isEmpty { end = token.range.upperBound; break }
                    }
                    cursor = token.range.upperBound
                } else {
                    cursor = markdown.index(after: cursor)
                }
            }
            guard let end else { index = open.range.upperBound; continue }
            let whole = open.range.lowerBound..<end
            if open.name == "equation" || open.name == "equation*" {
                let close = "\\end{\(open.name)}"
                let body = open.range.upperBound..<markdown.index(end, offsetBy: -close.count)
                result.append(Segment(range: whole, bodyRange: body, open: "\\begin{\(open.name)}", close: close,
                                      display: true, bare: false))
            } else {
                result.append(Segment(range: whole, bodyRange: whole, open: "", close: "", display: true, bare: true))
            }
            index = end
        }
        return result
    }

    private static func environmentToken(_ text: String, at index: String.Index, limit: String.Index) -> (begin: Bool, name: String, range: Range<String.Index>)? {
        let rest = text[index..<limit]
        let begin: Bool
        if rest.hasPrefix("\\begin{") { begin = true } else if rest.hasPrefix("\\end{") { begin = false } else { return nil }
        let nameStart = text.index(index, offsetBy: begin ? 7 : 5)
        guard let close = text[nameStart..<limit].firstIndex(of: "}") else { return nil }
        return (begin, String(text[nameStart..<close]), index..<text.index(after: close))
    }

    private static func isEscaped(_ text: String, _ index: String.Index) -> Bool {
        var count = 0
        var cursor = index
        while cursor > text.startIndex {
            cursor = text.index(before: cursor)
            guard text[cursor] == "\\" else { break }
            count += 1
        }
        return !count.isMultiple(of: 2)
    }

    /// Text outside fenced code blocks and code spans, which MarkdownView also excludes.
    private static func mathRanges(in markdown: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        var fence: (character: Character, count: Int)?
        var index = markdown.startIndex
        func close(at end: String.Index) {
            if let open = start, open < end { ranges.append(open..<end) }
            start = nil
        }
        while index < markdown.endIndex {
            let lineEnd = markdown[index...].firstIndex(of: "\n").map { markdown.index(after: $0) } ?? markdown.endIndex
            let line = markdown[index..<lineEnd]
            let trimmed = line.drop(while: { $0 == " " })
            let indent = line.count - trimmed.count
            let atLineStart = index == markdown.startIndex || markdown[markdown.index(before: index)] == "\n"
            if atLineStart, let character = trimmed.first, character == "`" || character == "~", indent <= 3 {
                let count = trimmed.prefix(while: { $0 == character }).count
                if count >= 3 {
                    if let active = fence {
                        if active.character == character, count >= active.count, trimmed.dropFirst(count).allSatisfy(\.isWhitespace) { fence = nil }
                    } else if character == "~" || !trimmed.dropFirst(count).contains("`") {
                        close(at: index)
                        fence = (character, count)
                    }
                    index = lineEnd
                    continue
                }
            }
            if fence != nil { index = lineEnd; continue }
            if start == nil { start = index }
            // Code spans on this line end a math range and start a new one after them.
            var cursor = index
            while cursor < lineEnd {
                if markdown[cursor] == "`", !isEscaped(markdown, cursor) {
                    let run = markdown[cursor..<markdown.endIndex].prefix(while: { $0 == "`" }).count
                    let delimiter = String(repeating: "`", count: run)
                    let after = markdown.index(cursor, offsetBy: run)
                    if let closing = codeSpanEnd(markdown, delimiter: delimiter, from: after) {
                        close(at: cursor)
                        start = closing
                        cursor = closing
                        continue
                    }
                    cursor = after
                    continue
                }
                cursor = markdown.index(after: cursor)
            }
            index = max(lineEnd, cursor)
        }
        close(at: markdown.endIndex)
        return ranges
    }

    /// The end of a code span opened by `delimiter`: a run of exactly that many backticks,
    /// within the same paragraph.
    private static func codeSpanEnd(_ text: String, delimiter: String, from start: String.Index) -> String.Index? {
        var cursor = start
        while cursor < text.endIndex {
            if text[cursor...].hasPrefix("\n\n") { return nil }
            if text[cursor] == "`" {
                let run = text[cursor...].prefix(while: { $0 == "`" }).count
                let end = text.index(cursor, offsetBy: run)
                if run == delimiter.count { return end }
                cursor = end
                continue
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }
}
