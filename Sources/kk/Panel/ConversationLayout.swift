import AppKit

/// Width is based on text, not the current viewport, so wrapping cannot cause a resize loop.
enum ConversationLayout {
    static func textWidth(_ text: String, fontSize: CGFloat = 14) -> CGFloat {
        text.split(separator: "\n", omittingEmptySubsequences: false).map {
            (String($0) as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: fontSize)]).width
        }.max() ?? 0
    }

    static func preferredWidth(messages: [ChatMessage], minimum: CGFloat, textSize: CGFloat) -> CGFloat {
        let maximum = max(UIConstants.panelWidth, minimum)
        let natural = messages.map { textWidth($0.content, fontSize: textSize) + 100 }.max() ?? minimum
        return min(maximum, max(minimum, ceil(natural / 40) * 40))
    }

    static func bubbleWidth(text: String, available: CGFloat) -> CGFloat {
        // Headings need slightly more room than body text. The renderer still owns wrapping.
        let size: CGFloat = text.contains("# ") ? 24 : 14
        return max(32, min(max(32, available - 40), ceil(textWidth(text, fontSize: size)) + 28))
    }

    static func height(content: CGFloat, chrome: CGFloat, minimum: CGFloat, streaming: Bool) -> CGFloat {
        let natural = content + chrome
        return min(UIConstants.panelMaxHeight, max(minimum, streaming ? ceil(natural / 24) * 24 : ceil(natural)))
    }
}
