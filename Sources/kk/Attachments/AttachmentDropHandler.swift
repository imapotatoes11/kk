import AppKit
import SwiftUI

/// Shared drop logic for the popup. Both the panel's hosting view and the prompt's text view
/// forward attachment drags here, so dropping anywhere on kk behaves the same way.
@MainActor
final class AttachmentDropHandler {
    var isEnabled: () -> Bool = { true }
    var onTargetChange: (Bool) -> Void = { _ in }
    var onDrop: (NSPasteboard) -> Bool = { _ in false }

    func accepts(_ info: NSDraggingInfo) -> Bool {
        isEnabled() && AttachmentPasteboard.hasAttachments(info.draggingPasteboard)
    }

    func update(_ info: NSDraggingInfo) -> NSDragOperation {
        let accepted = accepts(info)
        onTargetChange(accepted)
        return accepted ? .copy : []
    }

    func exit() {
        onTargetChange(false)
    }

    func perform(_ info: NSDraggingInfo) -> Bool {
        onTargetChange(false)
        guard accepts(info) else { return false }
        return onDrop(info.draggingPasteboard)
    }
}

/// The popup's root view. It accepts files and images dropped anywhere on the panel.
final class PanelHostingView: NSHostingView<AnyView> {
    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        registerForDraggedTypes(AttachmentPasteboard.dragTypes)
    }

    @MainActor @preconcurrency required init?(coder: NSCoder) { nil }

    private var dropHandler: AttachmentDropHandler? { (window as? KKPanel)?.attachmentDropHandler }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropHandler?.update(sender) ?? []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropHandler?.update(sender) ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropHandler?.exit()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        dropHandler?.exit()
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHandler?.accepts(sender) ?? false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHandler?.perform(sender) ?? false
    }
}
