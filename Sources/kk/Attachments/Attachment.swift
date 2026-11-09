import Foundation
import UniformTypeIdentifiers

/// Where an attachment comes from. File URLs come from Finder, drag and drop, or the file
/// picker; raw data comes from the pasteboard (screenshots, copied images or PDF selections).
enum AttachmentSource: Sendable, Equatable {
    /// `temporary` files were received from a file promise and are deleted after loading.
    case file(URL, temporary: Bool = false)
    case data(Data, filename: String, typeIdentifier: String)

    var filename: String {
        switch self {
        case .file(let url, _): url.lastPathComponent
        case .data(_, let filename, _): filename
        }
    }

    var contentType: UTType? {
        switch self {
        case .file(let url, _):
            (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? UTType(filenameExtension: url.pathExtension)
        case .data(_, _, let identifier):
            UTType(identifier)
        }
    }

    /// A best guess used to pick the chip icon before loading finishes.
    var expectedKind: Attachment.Kind {
        guard let type = contentType else { return .text }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        return .text
    }
}

struct Attachment: Identifiable, Sendable {
    enum Kind: String, Sendable {
        case image, text, pdf
    }

    enum Status: Sendable, Equatable {
        case processing(String?)
        case ready
        case failed(String)
    }

    let id: UUID
    var filename: String
    var kind: Kind
    var status: Status
    var content: AttachmentContent?

    init(id: UUID = UUID(), filename: String, kind: Kind, status: Status = .processing(nil), content: AttachmentContent? = nil) {
        self.id = id
        self.filename = filename
        self.kind = kind
        self.status = status
        self.content = content
    }

    static func ready(filename: String, kind: Kind, content: AttachmentContent) -> Attachment {
        Attachment(filename: filename, kind: kind, status: .ready, content: content)
    }

    var isProcessing: Bool { if case .processing = status { true } else { false } }
    var isReady: Bool { status == .ready && content != nil }
    var failureMessage: String? { if case .failed(let message) = status { message } else { nil } }

    var detail: String {
        switch status {
        case .processing(let progress): progress ?? "Reading…"
        case .failed(let message): message
        case .ready: content?.summary ?? ""
        }
    }

    var symbolName: String {
        switch kind {
        case .image: "photo"
        case .pdf: "doc.richtext"
        case .text: "doc.plaintext"
        }
    }
}

// The payload never changes once an attachment is ready, so comparing identity and status
// avoids hashing megabytes of image data on every streamed token.
extension Attachment: Equatable {
    static func == (lhs: Attachment, rhs: Attachment) -> Bool {
        lhs.id == rhs.id && lhs.filename == rhs.filename && lhs.kind == rhs.kind &&
            lhs.status == rhs.status && (lhs.content == nil) == (rhs.content == nil)
    }
}

struct AttachmentContent: Sendable {
    /// Text file contents or text extracted from a PDF.
    var text: String?
    /// JPEG data: the image itself, or rendered PDF pages.
    var images: [Data] = []
    var pageCount: Int?
    /// PDF pages whose text came from OCR.
    var ocrPages: [Int] = []
    /// Number of PDF pages included as images.
    var imagePageCount: Int { images.count }
    var truncated = false
    /// A small PNG used for chips.
    var thumbnail: Data?
    var summary: String
}

enum AttachmentError: LocalizedError, Equatable {
    case unsupportedType
    case folder
    case binaryFile
    case tooLarge(String)
    case unreadable
    case lockedPDF
    case emptyPDF
    case imageDecodeFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedType: "This file type isn't supported"
        case .folder: "Folders can't be attached"
        case .binaryFile: "Not a text file"
        case .tooLarge(let limit): "Larger than \(limit)"
        case .unreadable: "Couldn't read this file"
        case .lockedPDF: "PDF is password-protected"
        case .emptyPDF: "PDF has no pages"
        case .imageDecodeFailed: "Couldn't read this image"
        }
    }
}

enum AttachmentLimits {
    static let maxPerTurn = 10
    static let maxTextCharacters = 150_000
    static let maxTextFileBytes = 8_000_000
    static let maxImageFileBytes = 60_000_000
    static let maxPDFFileBytes = 150_000_000
    static let maxPDFTextPages = 300
    static let maxOCRPages = 40
    /// Pages with fewer visible characters than this are treated as scans and OCR'd.
    static let ocrThreshold = 20
    static let pageImageLongEdge: CGFloat = 1600
    static let ocrLongEdge: CGFloat = 2200
    static let pageImageOptions = [0, 4, 8, 16]
    static let defaultPageImages = 8
}
