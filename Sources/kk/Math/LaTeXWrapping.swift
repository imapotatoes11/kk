import AppKit
import SwiftMath
import SwiftUI

private struct WrapLaTeXKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var kkWrapLaTeX: Bool {
        get { self[WrapLaTeXKey.self] }
        set { self[WrapLaTeXKey.self] = newValue }
    }
}

/// Reflows display math locally, leaving copied/requested Markdown untouched.
/// Breaks only between top-level operators. Fractions, radicals, scripts, paired
/// delimiters and existing multiline environments remain intact.
enum LaTeXWrapping {
    @MainActor
    static func equation(_ source: String, width: CGFloat, fontSize: CGFloat) -> String {
        guard width > 40 else { return source }
        var error: NSError?
        guard let list = MTMathListBuilder.build(fromString: source, error: &error), error == nil,
              !list.atoms.contains(where: { $0.type == .table }), !containsColor(list) else { return source }
        let label = MTMathUILabel()
        label.fontSize = fontSize
        label.labelMode = .display
        func fits(_ atoms: [MTMathAtom]) -> Bool {
            label.mathList = MTMathList(atoms: atoms)
            return label.fittingSize.width <= width - 8
        }
        guard !fits(list.atoms) else { return source }
        var groups: [[MTMathAtom]] = []
        var group: [MTMathAtom] = []
        var depth = 0
        var barDelimiter: String?
        for atom in list.atoms {
            if depth == 0, barDelimiter == nil, !group.isEmpty, atom.type == .binaryOperator || atom.type == .relation {
                groups.append(group)
                group = []
            }
            group.append(atom)
            if atom.nucleus == "|" || atom.nucleus == "‖" {
                if barDelimiter == atom.nucleus { barDelimiter = nil }
                else if barDelimiter == nil { barDelimiter = atom.nucleus }
            }
            if atom.type == .open { depth += 1 }
            if atom.type == .close { depth = max(0, depth - 1) }
        }
        if !group.isEmpty { groups.append(group) }
        guard groups.count > 1 else { return source }
        var lines: [[MTMathAtom]] = []
        var line: [MTMathAtom] = []
        for group in groups {
            if !line.isEmpty, !fits(line + group) { lines.append(line); line = [] }
            line += group
        }
        if !line.isEmpty { lines.append(line) }
        guard lines.count > 1 else { return source }
        let body = lines.map { MTMathListBuilder.mathListToString(MTMathList(atoms: $0)) }.joined(separator: #" \\ "#)
        let wrapped = #"\begin{gather}"# + body + #"\end{gather}"#
        // Unsupported combinations fall back to the existing horizontal math scroller.
        guard MTMathListBuilder.build(fromString: wrapped, error: &error) != nil, error == nil else { return source }
        return wrapped
    }

    /// SwiftMath can't write colored atoms back to LaTeX, so colored equations aren't reflowed.
    private static func containsColor(_ list: MTMathList?) -> Bool {
        guard let list else { return false }
        return list.atoms.contains { atom in
            if [.color, .textcolor, .colorBox].contains(atom.type) { return true }
            if containsColor(atom.superScript) || containsColor(atom.subScript) { return true }
            switch atom {
            case let fraction as MTFraction: return containsColor(fraction.numerator) || containsColor(fraction.denominator)
            case let radical as MTRadical: return containsColor(radical.radicand) || containsColor(radical.degree)
            case let inner as MTInner: return containsColor(inner.innerList)
            case let line as MTOverLine: return containsColor(line.innerList)
            case let line as MTUnderLine: return containsColor(line.innerList)
            case let accent as MTAccent: return containsColor(accent.innerList)
            default: return false
            }
        }
    }

    @MainActor
    static func markdown(_ source: String, width: CGFloat, fontSize: CGFloat) -> String {
        var output = ""
        var index = source.startIndex
        var fence: (character: Character, count: Int)?
        func escaped(_ position: String.Index) -> Bool {
            var cursor = position
            var count = 0
            while cursor > source.startIndex {
                cursor = source.index(before: cursor)
                guard source[cursor] == "\\" else { break }
                count += 1
            }
            return !count.isMultiple(of: 2)
        }
        while index < source.endIndex {
            let atLineStart = index == source.startIndex || source[source.index(before: index)] == "\n"
            if atLineStart {
                let end = source[index...].firstIndex(of: "\n").map { source.index(after: $0) } ?? source.endIndex
                let line = source[index..<end]
                let trimmed = line.drop(while: { $0 == " " })
                let indent = line.count - trimmed.count
                if let character = trimmed.first, character == "`" || character == "~" {
                    let count = trimmed.prefix(while: { $0 == character }).count
                    if indent <= 3, count >= 3 {
                        if let active = fence {
                            if active.character == character, count >= active.count,
                               trimmed.dropFirst(count).allSatisfy(\.isWhitespace) { fence = nil }
                        } else { fence = (character, count) }
                        output += line; index = end; continue
                    }
                }
                if fence != nil || indent >= 4 || line.first == "\t" {
                    output += line; index = end; continue
                }
            }
            if source[index] == "`", !escaped(index) {
                let count = source[index...].prefix(while: { $0 == "`" }).count
                let delimiter = String(repeating: "`", count: count)
                let start = source.index(index, offsetBy: count)
                if let closing = source.range(of: delimiter, range: start..<source.endIndex) {
                    output += source[index..<closing.upperBound]; index = closing.upperBound; continue
                }
            }
            let pairs = [("$$", "$$"), (#"\["#, #"\]"#), (#"\begin{equation}"#, #"\end{equation}"#), (#"\begin{equation*}"#, #"\end{equation*}"#)]
            if !escaped(index), let pair = pairs.first(where: { source[index...].hasPrefix($0.0) }) {
                let start = source.index(index, offsetBy: pair.0.count)
                var search = start
                var closing: Range<String.Index>?
                while search < source.endIndex, let match = source.range(of: pair.1, range: search..<source.endIndex) {
                    if !escaped(match.lowerBound) { closing = match; break }
                    search = match.upperBound
                }
                if let closing {
                    let original = String(source[start..<closing.lowerBound])
                    output += pair.0 + equation(original, width: width, fontSize: fontSize) + pair.1
                    index = closing.upperBound; continue
                }
            }
            output.append(source[index])
            index = source.index(after: index)
        }
        return output
    }
}
