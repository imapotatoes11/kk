import Foundation

/// Finds fenced code blocks in Markdown so Mermaid diagrams can be validated and replaced.
enum MermaidExtractor {
    struct Block: Equatable {
        /// The fence's info-string language, lowercased (empty when absent).
        let language: String
        let code: String
        /// The text between the opening and closing fence lines.
        let codeRange: Range<String.Index>
        /// Leading whitespace of the opening fence, for blocks nested in lists.
        let indent: String
    }

    /// Mermaid blocks with both an opening and a closing fence. A block cut off by Stop or a
    /// dropped connection is incomplete and is skipped.
    static func blocks(in text: String) -> [Block] {
        fencedBlocks(in: text).filter { $0.language == "mermaid" }
    }

    static func fencedBlocks(in text: String) -> [Block] {
        var result: [Block] = []
        var open: (marker: Character, count: Int, indent: String, language: String, contentStart: String.Index)?
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let next = lineEnd < text.endIndex ? text.index(after: lineEnd) : text.endIndex
            let line = text[lineStart..<lineEnd]
            let indent = String(line.prefix { $0 == " " || $0 == "\t" })
            let rest = line.dropFirst(indent.count)
            if let fence = open {
                let run = rest.prefix { $0 == fence.marker }
                if run.count >= fence.count && rest.dropFirst(run.count).allSatisfy({ $0 == " " || $0 == "\t" || $0 == "\r" }) {
                    let codeRange = fence.contentStart..<lineStart
                    result.append(Block(language: fence.language, code: dedent(String(text[codeRange]), fence.indent), codeRange: codeRange, indent: fence.indent))
                    open = nil
                }
            } else if let marker = rest.first, marker == "`" || marker == "~" {
                let run = rest.prefix { $0 == marker }
                let info = rest.dropFirst(run.count).trimmingCharacters(in: .whitespaces)
                // Backtick fences can't have backticks in their info string (CommonMark).
                if run.count >= 3 && !(marker == "`" && info.contains("`")) {
                    let language = info.split(whereSeparator: { $0 == " " || $0 == "{" }).first.map { String($0).lowercased() } ?? ""
                    open = (marker, run.count, indent, language, next)
                }
            }
            lineStart = next
        }
        return result
    }

    /// The identity used to track a diagram's repair status across views and messages.
    static func key(_ code: String) -> String {
        code.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Replaces the first block whose code matches `original`, keeping the fence and its indent.
    static func replacing(_ original: String, with replacement: String, in text: String) -> String? {
        guard let block = blocks(in: text).first(where: { key($0.code) == key(original) }) else { return nil }
        let lines = key(replacement).components(separatedBy: "\n").map { $0.isEmpty ? $0 : block.indent + $0 }
        var updated = text
        updated.replaceSubrange(block.codeRange, with: lines.joined(separator: "\n") + "\n")
        return updated
    }

    /// The diagram in a repair reply: a Mermaid fence, any fence, or the bare reply.
    static func diagram(inReply reply: String) -> String? {
        let fences = fencedBlocks(in: reply)
        let code = fences.first(where: { $0.language == "mermaid" })?.code ?? fences.first?.code ?? reply
        let trimmed = key(code)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func dedent(_ code: String, _ indent: String) -> String {
        guard !indent.isEmpty else { return code }
        return code.components(separatedBy: "\n").map { line in
            var line = Substring(line)
            var removed = 0
            while removed < indent.count, let first = line.first, first == " " || first == "\t" {
                line = line.dropFirst()
                removed += 1
            }
            return String(line)
        }.joined(separator: "\n")
    }
}
