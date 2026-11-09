import AppKit
import SwiftUI

struct PromptEditor: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    var isDisabled: Bool
    var onSubmit: () -> Void
    var onCancel: (() -> Void)? = nil
    var registersAsComposer = true
    var accentColor: NSColor? = nil
    var onHeightChange: (CGFloat) -> Void = { _ in }
    /// Called on paste. Returns true when the pasteboard held attachments instead of text.
    var onPasteAttachments: (NSPasteboard) -> Bool = { _ in false }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PromptTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.onCancel = onCancel
        textView.onPasteAttachments = onPasteAttachments
        textView.string = text
        textView.font = .systemFont(ofSize: 14)
        textView.usesAdaptiveColorMappingForDarkAppearance = false
        applyTextColor(to: textView)
        textView.insertionPointColor = accentColor ?? .controlAccentColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let scrollView = PromptScrollView()
        scrollView.onHeightChange = onHeightChange
        scrollView.registersAsComposer = registersAsComposer
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        textView.onTextLayoutChange = { [weak scrollView] in scrollView?.measureContent() }
        DispatchQueue.main.async {
            scrollView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PromptTextView else { return }
        context.coordinator.parent = self
        textView.onSubmit = onSubmit
        textView.onCancel = onCancel
        textView.onPasteAttachments = onPasteAttachments
        textView.insertionPointColor = accentColor ?? .controlAccentColor
        (scrollView as? PromptScrollView)?.onHeightChange = onHeightChange
        textView.isEditable = !isDisabled
        if textView.string != text { textView.string = text }
        applyTextColor(to: textView)
        (scrollView as? PromptScrollView)?.measureContent()
        let shouldRefocus = !isDisabled && context.coordinator.wasDisabled
        context.coordinator.wasDisabled = isDisabled
        if shouldRefocus {
            DispatchQueue.main.async {
                scrollView.window?.makeFirstResponder(textView)
            }
        }
    }

    private func applyTextColor(to textView: NSTextView) {
        let color: NSColor = colorScheme == .dark ? .white : .black
        textView.textColor = color
        textView.typingAttributes[.foregroundColor] = color
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: storage.length))
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PromptEditor
        var wasDisabled = false

        init(_ parent: PromptEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            (textView.enclosingScrollView as? PromptScrollView)?.measureContent()
        }
    }
}

final class PromptScrollView: NSScrollView {
    var onHeightChange: (CGFloat) -> Void = { _ in }
    var registersAsComposer = true
    private var reportedHeight: CGFloat = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if registersAsComposer { (window as? KKPanel)?.promptEditor = documentView as? NSTextView }
    }

    override func layout() {
        super.layout()
        measureContent()
    }

    func measureContent() {
        guard let textView = documentView as? NSTextView,
              let container = textView.textContainer,
              let manager = textView.layoutManager,
              contentSize.width > 0 else { return }
        container.containerSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        let height = ceil(max(20, manager.usedRect(for: container).height) + textView.textContainerInset.height * 2)
        textView.setFrameSize(NSSize(width: contentSize.width, height: max(contentSize.height, height)))
        guard abs(height - reportedHeight) > 0.5 else { return }
        reportedHeight = height
        let callback = onHeightChange
        DispatchQueue.main.async { callback(height) }
    }
}

final class PromptTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onTextLayoutChange: (() -> Void)?
    var onPasteAttachments: ((NSPasteboard) -> Bool)?

    /// Attaches files, images, or PDF data from the pasteboard. Text pastes normally.
    func pasteAttachments(from pasteboard: NSPasteboard = .general) -> Bool {
        guard isEditable, AttachmentPasteboard.hasAttachments(pasteboard) else { return false }
        return onPasteAttachments?(pasteboard) ?? false
    }

    override func paste(_ sender: Any?) {
        if pasteAttachments() { return }
        super.paste(sender)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(paste(_:)), isEditable, AttachmentPasteboard.hasAttachments(.general) { return true }
        return super.validateUserInterfaceItem(item)
    }

    // A plain-text view would insert a dropped file's path. Attachment drags go to the shared
    // drop handler instead, so dropping on the question field matches the rest of the popup.
    private var dropHandler: AttachmentDropHandler? { (window as? KKPanel)?.attachmentDropHandler }

    private func isAttachmentDrag(_ sender: NSDraggingInfo) -> Bool {
        AttachmentPasteboard.hasAttachments(sender.draggingPasteboard) && dropHandler != nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isAttachmentDrag(sender) ? dropHandler!.update(sender) : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isAttachmentDrag(sender) ? dropHandler!.update(sender) : super.draggingUpdated(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropHandler?.exit()
        super.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isAttachmentDrag(sender) ? dropHandler!.accepts(sender) : super.prepareForDragOperation(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isAttachmentDrag(sender) ? dropHandler!.perform(sender) : super.performDragOperation(sender)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        if let sender, isAttachmentDrag(sender) { return }
        super.concludeDragOperation(sender)
    }

    override func didChangeText() {
        super.didChangeText()
        onTextLayoutChange?()
    }

    private var keyModifiers: NSEvent.ModifierFlags?

    override func keyDown(with event: NSEvent) {
        keyModifiers = event.modifierFlags
        defer { keyModifiers = nil }
        super.keyDown(with: event)
    }

    override func doCommand(by selector: Selector) {
        if selector == #selector(cancelOperation(_:)), !hasMarkedText(), let onCancel {
            onCancel()
            return
        }
        let newlineSelectors: Set<Selector> = [
            #selector(insertNewline(_:)),
            #selector(insertNewlineIgnoringFieldEditor(_:))
        ]
        guard newlineSelectors.contains(selector), !hasMarkedText() else {
            super.doCommand(by: selector)
            return
        }
        if (keyModifiers ?? NSApp.currentEvent?.modifierFlags)?.contains(.shift) == true {
            insertNewline(nil)
        } else {
            onSubmit?()
        }
    }
}
