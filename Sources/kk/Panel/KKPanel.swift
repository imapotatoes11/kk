import AppKit

final class KKPanel: NSPanel {
    var onEscape: (() -> Void)?
    var onCopyShortcut: (() -> Bool)?
    var onBeginDrag: (() -> Void)?
    var onDragFrame: ((NSRect, NSPoint) -> Void)?
    var onEndDrag: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            if let text = firstResponder as? NSTextView, text.selectedRange().length > 0 {
                return super.performKeyEquivalent(with: event)
            }
            if onCopyShortcut?() == true { return true }
        }
        return super.performKeyEquivalent(with: event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
