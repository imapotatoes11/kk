import AppKit
import SwiftUI

/// A native rectangular hit target over a SwiftUI label, including the empty cell edges.
struct PaletteButton<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let action: () -> Void
    let anchorAction: ((NSView) -> Void)?
    @ViewBuilder let label: () -> Label
    init(_ title: String, action: @escaping () -> Void, anchorAction: ((NSView) -> Void)? = nil, @ViewBuilder label: @escaping () -> Label) {
        self.title = title; self.action = action; self.anchorAction = anchorAction; self.label = label
    }
    var body: some View {
        label().opacity(isEnabled ? 1 : 0.4).allowsHitTesting(false).overlay { PaletteHitButton(title: title, action: action, anchorAction: anchorAction) }
    }
}

private struct PaletteHitButton: NSViewRepresentable {
    let title: String
    let action: () -> Void
    let anchorAction: ((NSView) -> Void)?
    @Environment(\.isEnabled) private var isEnabled
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSButton {
        let button = FirstClickButton()
        button.title = ""
        button.isBordered = false
        button.isTransparent = true
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.press(_:))
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = { button in anchorAction?(button); action() }
        button.isEnabled = isEnabled
        button.setAccessibilityLabel(title)
        button.toolTip = title
    }
    final class FirstClickButton: NSButton {
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    }
    final class Coordinator: NSObject {
        var action: ((NSButton) -> Void)?
        @objc func press(_ sender: NSButton) { action?(sender) }
    }
}
