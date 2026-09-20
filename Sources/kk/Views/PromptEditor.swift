import AppKit
import SwiftUI

struct PromptEditor: NSViewRepresentable {
    @Binding var text: String
    var isDisabled: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PromptTextView()
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
        textView.string = text
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = .labelColor
        textView.insertionPointColor = .controlAccentColor
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
        textView.textContainer?.containerSize = NSSize(width: 0, height: .greatestFiniteMagnitude)

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView
        DispatchQueue.main.async {
            scrollView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PromptTextView else { return }
        context.coordinator.parent = self
        textView.onSubmit = onSubmit
        textView.isEditable = !isDisabled
        if textView.string != text { textView.string = text }
        let shouldRefocus = !isDisabled && context.coordinator.wasDisabled
        context.coordinator.wasDisabled = isDisabled
        if shouldRefocus {
            DispatchQueue.main.async {
                scrollView.window?.makeFirstResponder(textView)
            }
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
        }
    }
}

private final class PromptTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func doCommand(by selector: Selector) -> Bool {
        let newlineSelectors: Set<Selector> = [
            #selector(insertNewline(_:)),
            #selector(insertNewlineIgnoringFieldEditor(_:))
        ]
        guard newlineSelectors.contains(selector) else { return super.doCommand(by: selector) }
        if hasMarkedText() { return super.doCommand(by: selector) }
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            insertNewline(nil)
        } else {
            onSubmit?()
        }
        return true
    }
}
