import Foundation

enum UIConstants {
    static let panelWidth: CGFloat = 680
    static let compactPanelWidth: CGFloat = 480
    static let panelMaxHeight: CGFloat = 620
    static let panelTopMargin: CGFloat = 88
    static let cornerRadius: CGFloat = 12
    static let outerPadding: CGFloat = 14
    static let sectionSpacing: CGFloat = 12
    static let previewMaxWidth: CGFloat = 560
    static let previewMaxHeight: CGFloat = 360
    static let scrollFollowThreshold: CGFloat = 40
}

enum CaptureConstants {
    static let maxLongEdge: CGFloat = 2560
    static let jpegQuality: CGFloat = 0.85
    static let fallbackLongEdge: CGFloat = 2048
    static let fallbackJPEGQuality: CGFloat = 0.75
    static let softMaxBytes = 2_500_000
}

enum Defaults {
    static let baseURL = "https://api.openai.com/v1"
    static let model = "gpt-5.6-luna"
}

enum KKCopy {
    static var systemPrompt: String { systemPrompt(diagrams: true) }

    static func systemPrompt(diagrams: Bool, customInstructions: String = "") -> String {
        let prompt = diagrams ? basePrompt + " " + diagramGuidance : basePrompt
        let custom = String(customInstructions.prefix(customInstructionsLimit)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !custom.isEmpty else { return prompt }
        return prompt + "\n\n" + customInstructionsPreamble + "\n<user_instructions>\n" + custom + "\n</user_instructions>"
    }

    /// Roughly a page of text; keeps every request's prompt overhead bounded.
    static let customInstructionsLimit = 4_000
    static let customInstructionsPreamble = """
    The user has provided the following custom instructions for how you should respond. Follow them in every answer unless they conflict with the user's current request, which takes priority.
    """

    static let diagramGuidance = """
    When a diagram would genuinely clarify the answer (a process, sequence, architecture, state machine, or set of relationships), you may include one as a Mermaid code block (```mermaid). It is drawn for the user. Keep diagrams small and focused, and still explain in text. Use valid Mermaid 11 syntax: put node labels that contain spaces, punctuation, or parentheses in double quotes (for example A["f(x) = 2x"]), and don't put HTML or Markdown inside labels. For math in a diagram, wrap it in double dollar signs inside a quoted label, for example A["$$\\frac{1}{2}mv^2$$"]; this works only in flowcharts and sequence diagrams, and single dollar signs aren't rendered as math.
    """

    static let diagramRepairPrompt = """
    You fix Mermaid diagram syntax. Reply with only the corrected diagram in a single ```mermaid code block, with no explanation. Keep the diagram's type, structure, meaning, and labels. Use valid Mermaid 11 syntax. Put node labels that contain spaces, punctuation, or parentheses in double quotes, and remove HTML or Markdown from labels. Keep any $$...$$ math in labels exactly as written.
    """

    static let mathRepairPrompt = """
    You fix LaTeX math that a limited renderer can't draw. It supports standard math-mode LaTeX: fractions, roots, scripts, Greek letters and common symbols, \\left and \\right, \\text, font commands such as \\mathbf and \\mathbb, accents, \\operatorname, and the environments aligned (two columns per row), gather, cases, matrix, pmatrix, bmatrix, and vmatrix. It doesn't support macros you define, \\tag, \\label, packages beyond amsmath, or text-mode commands outside \\text. For each expression, reply with a ```latex code block containing only the corrected expression, without $ or \\[ delimiters, in the order given, and nothing else. Keep the meaning and notation; change only what's needed to make it valid.
    """

    static let basePrompt = """
    You are kk, a concise assistant answering questions using the user's screen and attached files as context. Answer the user's question directly. Pay close attention to visible text, UI, code, diagrams, math, and errors. Use Markdown when useful. For math, use `$...$` for inline math and `$$...$$` for display math. Do not describe the screenshot unless it helps answer the question. Each user turn may include new desktop captures. Multiple attached images show separate connected displays, starting with the interaction display. Follow-up prompts may or may not be relevant to the attached desktop capture; use the conversation and the user's wording to decide whether the image is relevant. Do not assume the desktop has stayed the same between turns. The user may also attach files: text and PDF contents arrive inside <attachment> tags before the question, and attached images or PDF page images follow the screen captures, each introduced by a label with its file name. PDF text marked as recognized by OCR may contain recognition errors. If the user sends attachments without a question, briefly summarize what they contain and offer to help with them.
    """
}
