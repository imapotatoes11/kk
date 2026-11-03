import AppKit
import SwiftUI

struct PromptEditor: NSViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var text: String
    var isDisabled: Bool
    var onSubmit: () -> Void
    var accentColor: NSColor? = nil
    var onHeightChange: (CGFloat) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PromptTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        textView.delegate = context.coordinator
        textView.onSubmit = onSubmit
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
    private var reportedHeight: CGFloat = 0

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        (window as? KKPanel)?.promptEditor = documentView as? NSTextView
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

private final class PromptTextView: NSTextView {
    var onSubmit: (() -> Void)?
    var onTextLayoutChange: (() -> Void)?

    override func didChangeText() {
        super.didChangeText()
        onTextLayoutChange?()
    }

    override func doCommand(by selector: Selector) {
        let newlineSelectors: Set<Selector> = [
            #selector(insertNewline(_:)),
            #selector(insertNewlineIgnoringFieldEditor(_:))
        ]
        guard newlineSelectors.contains(selector), !hasMarkedText() else {
            super.doCommand(by: selector)
            return
        }
        if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
            insertNewline(nil)
        } else {
            onSubmit?()
        }
    }
}
