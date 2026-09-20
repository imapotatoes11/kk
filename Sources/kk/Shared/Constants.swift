import Foundation

enum UIConstants {
    static let panelWidth: CGFloat = 680
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
    static let systemPrompt = """
    You are kk, a concise assistant answering questions using the user's screen as visual context. Answer the user's question directly. Pay close attention to visible text, UI, code, diagrams, math, and errors. Use Markdown when useful. For math, use `$...$` for inline math and `$$...$$` for display math. Do not describe the screenshot unless it helps answer the question.
    """
}
