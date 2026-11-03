import AppKit
import SwiftUI

struct AnnotationShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt
    var label: String
    static let modifierMask: NSEvent.ModifierFlags = [.command, .control, .option, .shift]
    func matches(_ event: NSEvent) -> Bool {
        event.keyCode == keyCode && event.modifierFlags.intersection(Self.modifierMask).rawValue == modifiers
    }
    static let defaults: [String: Self] = [
        "freehand": .init(keyCode: 3, modifiers: 0, label: "F"),
        "rectangle": .init(keyCode: 15, modifiers: 0, label: "R"),
        "ellipse": .init(keyCode: 14, modifiers: 0, label: "E"),
        "arrow": .init(keyCode: 0, modifiers: 0, label: "A"),
        "annotate": .init(keyCode: 0, modifiers: NSEvent.ModifierFlags([.control, .shift]).rawValue, label: "⌃⇧A"),
        "focus": .init(keyCode: 49, modifiers: 0, label: "Space")
    ]
}

struct AnnotationShortcutRecorder: NSViewRepresentable {
    @Binding var bindings: [String: AnnotationShortcut]
    let action: String
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        if !button.recording { button.title = bindings[action]?.label ?? "Unassigned" }
        button.onRecord = { shortcut in
            // One action per combination; moving a key removes its previous assignment.
            if let shortcut {
                for (key, existing) in bindings where key != action && existing.keyCode == shortcut.keyCode && existing.modifiers == shortcut.modifiers { bindings.removeValue(forKey: key) }
            }
            bindings[action] = shortcut
        }
    }
    final class RecorderButton: NSButton {
        var recording = false
        private var previousTitle = ""
        var onRecord: ((AnnotationShortcut?) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func mouseDown(with event: NSEvent) {
            previousTitle = title
            recording = true
            title = "Press keys…"
            window?.makeFirstResponder(self)
        }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event)
            return true
        }
        override func keyDown(with event: NSEvent) {
            guard recording else { return super.keyDown(with: event) }
            if event.keyCode == 53 { recording = false; title = previousTitle; return }
            if [51, 117].contains(event.keyCode) { onRecord?(nil); title = "Unassigned"; recording = false; return }
            let flags = event.modifierFlags.intersection(AnnotationShortcut.modifierMask)
            let prefix = (flags.contains(.control) ? "⌃" : "") + (flags.contains(.option) ? "⌥" : "") + (flags.contains(.shift) ? "⇧" : "") + (flags.contains(.command) ? "⌘" : "")
            let key = event.keyCode == 49 ? "Space" : (event.charactersIgnoringModifiers ?? "").uppercased()
            guard !key.isEmpty else { return }
            let shortcut = AnnotationShortcut(keyCode: event.keyCode, modifiers: flags.rawValue, label: prefix + key)
            onRecord?(shortcut)
            title = shortcut.label
            recording = false
        }
    }
}
