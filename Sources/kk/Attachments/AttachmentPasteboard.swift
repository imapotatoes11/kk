import AppKit
import UniformTypeIdentifiers

/// Reads attachments from the general pasteboard (paste) or a dragging pasteboard (drop).
enum AttachmentPasteboard {
    static let imageTypes: [NSPasteboard.PasteboardType] = [
        .png, .tiff,
        .init(UTType.jpeg.identifier), .init(UTType.heic.identifier), .init(UTType.heif.identifier),
        .init(UTType.webP.identifier), .init(UTType.gif.identifier), .init("public.avif")
    ]
    static let textTypes: [NSPasteboard.PasteboardType] = [.string, .rtf, .rtfd, .html]
    static let dragTypes: [NSPasteboard.PasteboardType] = [.fileURL, .pdf] + imageTypes
        + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    /// Whether the pasteboard holds something kk should attach rather than paste as text.
    static func hasAttachments(_ pasteboard: NSPasteboard) -> Bool {
        if !fileURLs(pasteboard).isEmpty { return true }
        if hasFilePromises(pasteboard) { return true }
        return dataType(pasteboard) != nil
    }

    /// Attachments in priority order:
    /// 1. File URLs. A Finder copy also carries the file's icon as TIFF, which must be ignored.
    /// 2. PDF data, such as pages copied from Preview.
    /// 3. Image data, such as screenshots copied with ⌘⌃⇧4.
    /// Rich text copied from a document can include PDF or image renderings of the selection, so
    /// data is used only when the source ranks it ahead of its text representations.
    static func sources(from pasteboard: NSPasteboard) -> [AttachmentSource] {
        let urls = fileURLs(pasteboard)
        if !urls.isEmpty { return urls.map { .file($0) } }
        guard let type = dataType(pasteboard), let data = pasteboard.data(forType: type) else { return [] }
        let uti = UTType(type.rawValue) ?? .data
        if uti.conforms(to: .pdf) {
            return [.data(data, filename: "Pasted PDF.pdf", typeIdentifier: UTType.pdf.identifier)]
        }
        let ext = uti.preferredFilenameExtension ?? "png"
        return [.data(data, filename: "Pasted image.\(ext)", typeIdentifier: uti.identifier)]
    }

    static func fileURLs(_ pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
    }

    static func hasFilePromises(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self], options: nil)
    }

    static func dataType(_ pasteboard: NSPasteboard) -> NSPasteboard.PasteboardType? {
        let types = pasteboard.types ?? []
        guard let dataIndex = types.firstIndex(where: { $0 == .pdf || imageTypes.contains($0) }) else { return nil }
        if let textIndex = types.firstIndex(where: { textTypes.contains($0) }), textIndex < dataIndex { return nil }
        return types[dataIndex]
    }

    /// Receives promised files (for example, photos dragged from Photos) into a private
    /// temporary folder. Each file is deleted after it has been loaded.
    @MainActor
    static func receivePromisedFiles(from pasteboard: NSPasteboard, handler: @escaping @MainActor ([AttachmentSource]) -> Void) -> Bool {
        guard let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
              !receivers.isEmpty else { return false }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kk-drops-\(UUID().uuidString)", isDirectory: true)
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) } catch { return false }
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: directory, options: [:], operationQueue: queue) { url, error in
                guard error == nil else { return }
                Task { @MainActor in handler([.file(url, temporary: true)]) }
            }
        }
        return true
    }
}
