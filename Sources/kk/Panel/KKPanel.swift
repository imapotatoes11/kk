import AppKit

final class KKPanel: NSPanel {
    weak var promptEditor: NSTextView?
    var attachmentDropHandler: AttachmentDropHandler?

    func focusPrompt() {
        orderFrontRegardless()
        makeKey()
        if let promptEditor, promptEditor.isEditable { makeFirstResponder(promptEditor) }
    }

    var onExpandShortcut: ((NSEvent) -> Bool)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onExpandShortcut?(event) == true { return }
        super.sendEvent(event)
    }

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
        // Handle ⌘V here so pasted images and files attach even when the Edit menu would
        // disable Paste for a plain-text field.
        if event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
           event.charactersIgnoringModifiers?.lowercased() == "v",
           let editor = firstResponder as? PromptTextView, editor.pasteAttachments() {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
