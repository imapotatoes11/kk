import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import Vision

/// Converts files and pasted data into payloads the chat request can carry: JPEG images for
/// any format ImageIO decodes (including HEIC, HEIF, WebP, and AVIF), decoded text for text
/// files, and extracted or OCR'd text plus optional page images for PDFs.
///
/// Loading is synchronous and CPU-bound; callers run it off the main actor.
enum AttachmentLoader {
    struct Options: Sendable, Equatable {
        /// The number of leading PDF pages to include as images. Zero sends text only.
        var pdfPageImageLimit: Int = AttachmentLimits.defaultPageImages
    }

    struct Loaded: Sendable {
        let kind: Attachment.Kind
        let content: AttachmentContent
    }

    static func load(_ source: AttachmentSource, options: Options = Options(), progress: @Sendable (String) -> Void = { _ in }) throws -> Loaded {
        defer {
            if case .file(let url, true) = source { try? FileManager.default.removeItem(at: url) }
        }
        var fileSize: Int?
        if case .file(let url, _) = source {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey])
            if values?.isDirectory == true && values?.isPackage != true { throw AttachmentError.folder }
            if values?.isPackage == true { throw AttachmentError.unsupportedType }
            fileSize = values?.fileSize
        }
        let type = source.contentType

        if type?.conforms(to: .pdf) == true {
            try check(fileSize, against: AttachmentLimits.maxPDFFileBytes)
            let document: PDFDocument? = switch source {
            case .file(let url, _): PDFDocument(url: url)
            case .data(let data, _, _): PDFDocument(data: data)
            }
            return Loaded(kind: .pdf, content: try loadPDF(document, options: options, progress: progress))
        }

        // SVG is an image type that ImageIO can't draw; send its markup as text instead.
        if let type, type.conforms(to: .image), !type.conforms(to: .svg) {
            try check(fileSize, against: AttachmentLimits.maxImageFileBytes)
            let imageSource: CGImageSource? = switch source {
            case .file(let url, _): CGImageSourceCreateWithURL(url as CFURL, nil)
            case .data(let data, _, _): CGImageSourceCreateWithData(data as CFData, nil)
            }
            guard let imageSource else { throw AttachmentError.imageDecodeFailed }
            return Loaded(kind: .image, content: try loadImage(imageSource, type: type))
        }

        if let type, isKnownBinary(type) { throw AttachmentError.unsupportedType }
        try check(fileSize, against: AttachmentLimits.maxTextFileBytes)
        let data: Data
        switch source {
        case .file(let url, _):
            guard let contents = try? Data(contentsOf: url) else { throw AttachmentError.unreadable }
            data = contents
        case .data(let contents, _, _):
            data = contents
        }
        if data.count > AttachmentLimits.maxTextFileBytes { throw AttachmentError.tooLarge(byteLabel(AttachmentLimits.maxTextFileBytes)) }
        return Loaded(kind: .text, content: try loadText(data))
    }

    // MARK: - Text

    static func loadText(_ data: Data) throws -> AttachmentContent {
        let decoded = try TextFileDecoder.decode(data)
        var text = decoded.text
        var truncated = false
        if text.count > AttachmentLimits.maxTextCharacters {
            text = String(text.prefix(AttachmentLimits.maxTextCharacters))
            truncated = true
        }
        let lines = text.isEmpty ? 0 : text.reduce(into: 1) { count, character in if character == "\n" { count += 1 } }
        var summary = lines == 1 ? "1 line" : "\(lines) lines"
        switch decoded.encoding {
        case .utf16LittleEndian, .utf16BigEndian: summary += " · UTF-16"
        case .utf32LittleEndian, .utf32BigEndian: summary += " · UTF-32"
        case .windowsCP1252: summary += " · Windows-1252"
        default: break
        }
        if truncated { summary += " · truncated" }
        return AttachmentContent(text: text, truncated: truncated, summary: summary)
    }

    // MARK: - Images

    static func loadImage(_ source: CGImageSource, type: UTType?) throws -> AttachmentContent {
        guard CGImageSourceGetCount(source) > 0 else { throw AttachmentError.imageDecodeFailed }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        var width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        var height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        if let orientation = properties[kCGImagePropertyOrientation] as? UInt32, (5...8).contains(orientation) {
            swap(&width, &height)
        }
        let longEdge = max(width, height)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Applies EXIF orientation, so photos from phones arrive upright.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longEdge > 0 ? min(longEdge, Int(CaptureConstants.maxLongEdge)) : Int(CaptureConstants.maxLongEdge),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw AttachmentError.imageDecodeFailed
        }
        if width == 0 || height == 0 { width = image.width; height = image.height }
        guard let jpeg = try? ImageProcessor.jpegData(from: ImageProcessor.flattenedOnWhite(image)) else {
            throw AttachmentError.imageDecodeFailed
        }
        let format = (type?.preferredFilenameExtension ?? "image").uppercased()
        return AttachmentContent(images: [jpeg], thumbnail: ImageProcessor.thumbnailPNG(from: image), summary: "\(format) · \(width)×\(height)")
    }

    // MARK: - PDFs

    static func loadPDF(_ document: PDFDocument?, options: Options, progress: @Sendable (String) -> Void) throws -> AttachmentContent {
        guard let document else { throw AttachmentError.unreadable }
        if document.isLocked { throw AttachmentError.lockedPDF }
        let pageCount = document.pageCount
        guard pageCount > 0 else { throw AttachmentError.emptyPDF }

        let textPages = min(pageCount, AttachmentLimits.maxPDFTextPages)
        var sections: [String] = []
        var ocrPages: [Int] = []
        var ocrBudget = AttachmentLimits.maxOCRPages
        for index in 0..<textPages {
            if Task.isCancelled { throw CancellationError() }
            guard let page = document.page(at: index) else { continue }
            var text = (page.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var usedOCR = false
            // Scanned pages have no text layer, or only a few stray characters.
            if visibleCount(text) < AttachmentLimits.ocrThreshold && ocrBudget > 0 {
                ocrBudget -= 1
                progress("Reading page \(index + 1)/\(pageCount)")
                if let image = render(page, longEdge: AttachmentLimits.ocrLongEdge),
                   let recognized = recognizeText(in: image),
                   visibleCount(recognized) > visibleCount(text) {
                    text = recognized
                    usedOCR = true
                    ocrPages.append(index + 1)
                }
            }
            sections.append("[Page \(index + 1)\(usedOCR ? ", text recognized by OCR" : "")]\n\(text.isEmpty ? "(no text on this page)" : text)")
        }

        var text = sections.joined(separator: "\n\n")
        var truncated = textPages < pageCount
        if text.count > AttachmentLimits.maxTextCharacters {
            text = String(text.prefix(AttachmentLimits.maxTextCharacters))
            truncated = true
        }

        var images: [Data] = []
        let imagePages = min(pageCount, max(0, options.pdfPageImageLimit))
        for index in 0..<imagePages {
            if Task.isCancelled { throw CancellationError() }
            progress("Rendering page \(index + 1)/\(imagePages)")
            guard let page = document.page(at: index),
                  let image = render(page, longEdge: AttachmentLimits.pageImageLongEdge),
                  let jpeg = try? ImageProcessor.jpegData(from: image, longEdge: AttachmentLimits.pageImageLongEdge, quality: 0.8)
            else { continue }
            images.append(jpeg)
        }

        let thumbnail = document.page(at: 0).flatMap { render($0, longEdge: 96) }.flatMap { ImageProcessor.thumbnailPNG(from: $0) }
        var summary = pageCount == 1 ? "1 page" : "\(pageCount) pages"
        if !ocrPages.isEmpty { summary += " · OCR" }
        if truncated { summary += " · truncated" }
        return AttachmentContent(text: text, images: images, pageCount: pageCount, ocrPages: ocrPages, truncated: truncated, thumbnail: thumbnail, summary: summary)
    }

    static func render(_ page: PDFPage, longEdge: CGFloat) -> CGImage? {
        var size = page.bounds(for: .mediaBox).size
        if !page.rotation.isMultiple(of: 180) { size = CGSize(width: size.height, height: size.width) }
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(4, longEdge / max(size.width, size.height))
        let pixels = CGSize(width: max(1, floor(size.width * scale)), height: max(1, floor(size.height * scale)))
        // `thumbnail(of:for:)` applies the page rotation and crop box offsets.
        let image = page.thumbnail(of: pixels, for: .mediaBox)
        var rect = CGRect(origin: .zero, size: pixels)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        return ImageProcessor.flattenedOnWhite(cgImage)
    }

    static func recognizeText(in image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        do { try VNImageRequestHandler(cgImage: image).perform([request]) } catch { return nil }
        let lines = request.results?.compactMap { $0.topCandidates(1).first?.string } ?? []
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    static func visibleCount(_ text: String) -> Int {
        text.reduce(0) { $0 + ($1.isWhitespace ? 0 : 1) }
    }

    static func isKnownBinary(_ type: UTType) -> Bool {
        [UTType.archive, .audiovisualContent, .executable, .diskImage, .font, .bundle, .package]
            .contains { type.conforms(to: $0) }
    }

    private static func check(_ size: Int?, against limit: Int) throws {
        if let size, size > limit { throw AttachmentError.tooLarge(byteLabel(limit)) }
    }

    static func byteLabel(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
