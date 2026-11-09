import AppKit
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import kk

// MARK: - Text decoding

final class TextFileDecoderTests: XCTestCase {
    func testUTF8WithAndWithoutBOM() throws {
        XCTAssertEqual(try TextFileDecoder.decode(Data("print('héllo')\n".utf8)).text, "print('héllo')\n")
        let bom = Data([0xEF, 0xBB, 0xBF]) + Data("x = 1".utf8)
        let decoded = try TextFileDecoder.decode(bom)
        XCTAssertEqual(decoded.text, "x = 1")
        XCTAssertEqual(decoded.encoding, .utf8)
    }

    func testUTF16BothByteOrdersWithBOM() throws {
        let text = "Windows notes — café ✓\nline 2"
        let little = Data([0xFF, 0xFE]) + text.data(using: .utf16LittleEndian)!
        let big = Data([0xFE, 0xFF]) + text.data(using: .utf16BigEndian)!
        XCTAssertEqual(try TextFileDecoder.decode(little).text, text)
        XCTAssertEqual(try TextFileDecoder.decode(little).encoding, .utf16LittleEndian)
        XCTAssertEqual(try TextFileDecoder.decode(big).text, text)
        XCTAssertEqual(try TextFileDecoder.decode(big).encoding, .utf16BigEndian)
    }

    func testUTF16LittleEndianWithoutBOMFromWindowsTools() throws {
        let text = "Get-Process | Out-File procs.txt\r\nName  Id\r\n"
        let decoded = try TextFileDecoder.decode(text.data(using: .utf16LittleEndian)!)
        XCTAssertEqual(decoded.encoding, .utf16LittleEndian)
        XCTAssertEqual(decoded.text, "Get-Process | Out-File procs.txt\nName  Id\n", "CRLF is normalized to LF")
    }

    func testUTF32WithBOM() throws {
        let data = Data([0xFF, 0xFE, 0x00, 0x00]) + "λ".data(using: .utf32LittleEndian)!
        XCTAssertEqual(try TextFileDecoder.decode(data).text, "λ")
    }

    func testWindows1252Fallback() throws {
        // "café – 50€" in Windows-1252; these bytes are invalid UTF-8.
        let data = Data([0x63, 0x61, 0x66, 0xE9, 0x20, 0x96, 0x20, 0x35, 0x30, 0x80])
        let decoded = try TextFileDecoder.decode(data)
        XCTAssertEqual(decoded.encoding, .windowsCP1252)
        XCTAssertEqual(decoded.text, "café – 50€")
    }

    func testBinaryDataIsRejected() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x01, 0xFF])
        XCTAssertThrowsError(try TextFileDecoder.decode(png)) { XCTAssertEqual($0 as? AttachmentError, .binaryFile) }
        let controls = Data((0..<200).map { UInt8($0 % 8 + 1) })
        XCTAssertThrowsError(try TextFileDecoder.decode(controls))
    }

    func testOldMacLineEndingsAndEmptyFile() throws {
        XCTAssertEqual(try TextFileDecoder.decode(Data("a\rb".utf8)).text, "a\nb")
        XCTAssertEqual(try TextFileDecoder.decode(Data()).text, "")
    }
}

// MARK: - Loading files

final class AttachmentLoaderTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("kk-attachment-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testSourceAndTextFilesLoadAsText() throws {
        let url = directory.appendingPathComponent("main.py")
        try Data("def f():\n    return 1\n".utf8).write(to: url)
        let loaded = try AttachmentLoader.load(.file(url))
        XCTAssertEqual(loaded.kind, .text)
        XCTAssertEqual(loaded.content.text, "def f():\n    return 1\n")
        XCTAssertEqual(loaded.content.summary, "3 lines")

        for name in ["notes.md", "data.json", "Makefile", "config.yaml"] {
            let file = directory.appendingPathComponent(name)
            try Data("value".utf8).write(to: file)
            XCTAssertEqual(try AttachmentLoader.load(.file(file)).content.text, "value", name)
        }
    }

    func testUTF16TextFileReportsEncoding() throws {
        let url = directory.appendingPathComponent("log.txt")
        try (Data([0xFF, 0xFE]) + "hello".data(using: .utf16LittleEndian)!).write(to: url)
        let loaded = try AttachmentLoader.load(.file(url))
        XCTAssertEqual(loaded.content.text, "hello")
        XCTAssertTrue(loaded.content.summary.contains("UTF-16"))
    }

    func testLongTextIsTruncated() throws {
        let text = String(repeating: "a", count: AttachmentLimits.maxTextCharacters + 10)
        let content = try AttachmentLoader.loadText(Data(text.utf8))
        XCTAssertTrue(content.truncated)
        XCTAssertEqual(content.text?.count, AttachmentLimits.maxTextCharacters)
    }

    func testFoldersArchivesAndBinaryFilesAreRejected() throws {
        XCTAssertThrowsError(try AttachmentLoader.load(.file(directory))) { XCTAssertEqual($0 as? AttachmentError, .folder) }
        let zip = directory.appendingPathComponent("bundle.zip")
        try Data([0x50, 0x4B, 0x03, 0x04, 0, 0]).write(to: zip)
        XCTAssertThrowsError(try AttachmentLoader.load(.file(zip))) { XCTAssertEqual($0 as? AttachmentError, .unsupportedType) }
        let unknown = directory.appendingPathComponent("blob.bin")
        try Data([0x00, 0x01, 0x02, 0x00, 0xFF, 0x00, 0x10]).write(to: unknown)
        XCTAssertThrowsError(try AttachmentLoader.load(.file(unknown)))
    }

    func testTemporaryPromisedFilesAreDeletedAfterLoading() throws {
        let url = directory.appendingPathComponent("promised.txt")
        try Data("x".utf8).write(to: url)
        _ = try AttachmentLoader.load(.file(url, temporary: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testTransparentPNGBecomesJPEGOnWhite() throws {
        let image = try XCTUnwrap(Self.makeImage(width: 40, height: 20, color: nil))
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        let loaded = try AttachmentLoader.load(.data(png, filename: "Pasted image.png", typeIdentifier: UTType.png.identifier))
        XCTAssertEqual(loaded.kind, .image)
        let jpeg = try XCTUnwrap(loaded.content.images.first)
        XCTAssertEqual(UTType(CGImageSourceGetType(try XCTUnwrap(CGImageSourceCreateWithData(jpeg as CFData, nil)))! as String), .jpeg)
        let decoded = try XCTUnwrap(ImageProcessor.cgImage(from: jpeg))
        XCTAssertEqual(decoded.width, 40)
        XCTAssertGreaterThan(Self.averageBrightness(decoded), 0.95, "Transparent pixels must flatten to white, not black")
        XCTAssertEqual(loaded.content.summary, "PNG · 40×20")
        XCTAssertNotNil(loaded.content.thumbnail)
    }

    func testHEICImagesDecode() throws {
        let image = try XCTUnwrap(Self.makeImage(width: 64, height: 32, color: CGColor(red: 1, green: 0, blue: 0, alpha: 1)))
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil) else {
            throw XCTSkip("This Mac can't encode HEIC fixtures")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw XCTSkip("This Mac can't encode HEIC fixtures") }
        let url = directory.appendingPathComponent("photo.heic")
        try (data as Data).write(to: url)
        let loaded = try AttachmentLoader.load(.file(url))
        XCTAssertEqual(loaded.kind, .image)
        XCTAssertEqual(ImageProcessor.cgImage(from: loaded.content.images[0])?.width, 64)
        XCTAssertTrue(loaded.content.summary.hasPrefix("HEIC"))
    }

    func testWebPImagesDecode() throws {
        // 1×1 lossless and lossy WebP files.
        for base64 in ["UklGRhoAAABXRUJQVlA4TA0AAAAvAAAAEAcQERGIiP4HAA==", "UklGRiIAAABXRUJQVlA4IBYAAAAwAQCdASoBAAEADsD+JaQAA3AAAAAA"] {
            let data = try XCTUnwrap(Data(base64Encoded: base64))
            let loaded = try AttachmentLoader.load(.data(data, filename: "sticker.webp", typeIdentifier: UTType.webP.identifier))
            XCTAssertEqual(loaded.kind, .image)
            XCTAssertEqual(ImageProcessor.cgImage(from: loaded.content.images[0])?.width, 1)
        }
    }

    func testEXIFOrientationIsApplied() throws {
        let image = try XCTUnwrap(Self.makeImage(width: 60, height: 20, color: CGColor(red: 0, green: 0, blue: 1, alpha: 1)))
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let loaded = try AttachmentLoader.load(.data(data as Data, filename: "phone.jpg", typeIdentifier: UTType.jpeg.identifier))
        let decoded = try XCTUnwrap(ImageProcessor.cgImage(from: loaded.content.images[0]))
        XCTAssertEqual(decoded.width, 20)
        XCTAssertEqual(decoded.height, 60)
        XCTAssertEqual(loaded.content.summary, "JPEG · 20×60")
    }

    func testLargeImagesAreDownscaled() throws {
        let image = try XCTUnwrap(Self.makeImage(width: 5000, height: 1000, color: CGColor(red: 0, green: 1, blue: 0, alpha: 1)))
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        let loaded = try AttachmentLoader.load(.data(png, filename: "wide.png", typeIdentifier: UTType.png.identifier))
        XCTAssertEqual(ImageProcessor.cgImage(from: loaded.content.images[0])?.width, Int(CaptureConstants.maxLongEdge))
    }

    func testTextPDFExtractsTextAndPageImages() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("docs/previews/problem-set.pdf")
        let document = try XCTUnwrap(PDFDocument(url: url))
        let loaded = try AttachmentLoader.load(.file(url), options: .init(pdfPageImageLimit: 1))
        XCTAssertEqual(loaded.kind, .pdf)
        XCTAssertEqual(loaded.content.pageCount, document.pageCount)
        XCTAssertTrue(loaded.content.text?.contains("[Page 1]") == true)
        XCTAssertTrue(loaded.content.ocrPages.isEmpty, "Pages with a text layer don't need OCR")
        XCTAssertEqual(loaded.content.images.count, 1)
        XCTAssertNotNil(loaded.content.thumbnail)

        let textOnly = try AttachmentLoader.load(.file(url), options: .init(pdfPageImageLimit: 0))
        XCTAssertTrue(textOnly.content.images.isEmpty)
    }

    func testScannedPDFUsesOCR() throws {
        let pdf = try Self.makeScannedPDF(text: "INVOICE TOTAL 4821")
        let loaded = try AttachmentLoader.load(.data(pdf, filename: "scan.pdf", typeIdentifier: UTType.pdf.identifier), options: .init(pdfPageImageLimit: 8))
        XCTAssertEqual(loaded.content.ocrPages, [1])
        XCTAssertTrue(loaded.content.text?.contains("recognized by OCR") == true)
        XCTAssertTrue(loaded.content.text?.uppercased().contains("INVOICE") == true, loaded.content.text ?? "")
        XCTAssertTrue(loaded.content.text?.contains("4821") == true, loaded.content.text ?? "")
        XCTAssertEqual(loaded.content.images.count, 1, "Page images never exceed the page count")
        XCTAssertTrue(loaded.content.summary.contains("OCR"))
    }

    func testLockedPDFFailsCleanly() throws {
        let document = PDFDocument(data: try Self.makeScannedPDF(text: "secret"))!
        let url = directory.appendingPathComponent("locked.pdf")
        XCTAssertTrue(document.write(to: url, withOptions: [.userPasswordOption: "user", .ownerPasswordOption: "owner"]))
        XCTAssertThrowsError(try AttachmentLoader.load(.file(url))) { XCTAssertEqual($0 as? AttachmentError, .lockedPDF) }
    }

    // MARK: Fixtures

    static func makeImage(width: Int, height: Int, color: CGColor?) -> CGImage? {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        if let color { context?.setFillColor(color); context?.fill(CGRect(x: 0, y: 0, width: width, height: height)) }
        return context?.makeImage()
    }

    static func averageBrightness(_ image: CGImage) -> Double {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let pixel = context.data!.bindMemory(to: UInt8.self, capacity: 4)
        return (Double(pixel[0]) + Double(pixel[1]) + Double(pixel[2])) / (3 * 255)
    }

    /// A one-page PDF whose only content is a picture of text, like a scanned document.
    static func makeScannedPDF(text: String) throws -> Data {
        let size = NSSize(width: 1224, height: 1584)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        (text as NSString).draw(at: NSPoint(x: 120, y: 1300), withAttributes: [.font: NSFont.systemFont(ofSize: 72, weight: .bold), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        let image = try XCTUnwrap(bitmap.cgImage)

        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.draw(image, in: box)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}

// MARK: - Pasteboard

final class AttachmentPasteboardTests: XCTestCase {
    private func pasteboard() -> NSPasteboard {
        let board = NSPasteboard(name: .init("kk-tests-\(UUID().uuidString)"))
        board.clearContents()
        return board
    }

    func testFinderCopyAttachesTheFileNotItsIcon() throws {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("report.pdf")
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        item.setData(NSImage(systemSymbolName: "doc", accessibilityDescription: nil)!.tiffRepresentation!, forType: .tiff)
        item.setString("report.pdf", forType: .string)
        board.writeObjects([item])
        XCTAssertTrue(AttachmentPasteboard.hasAttachments(board))
        XCTAssertEqual(AttachmentPasteboard.sources(from: board), [.file(url)])
    }

    func testScreenshotDataAttachesAsImage() throws {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        board.setData(png, forType: .png)
        XCTAssertEqual(AttachmentPasteboard.sources(from: board), [.data(png, filename: "Pasted image.png", typeIdentifier: UTType.png.identifier)])
    }

    func testPlainTextPastesAsText() {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        board.setString("just words", forType: .string)
        XCTAssertFalse(AttachmentPasteboard.hasAttachments(board))
        XCTAssertTrue(AttachmentPasteboard.sources(from: board).isEmpty)
    }

    func testRichTextWithRenderedPDFStillPastesAsText() {
        // Word processors put RTF and string ahead of PDF or image renderings of the selection.
        let board = pasteboard()
        defer { board.releaseGlobally() }
        board.declareTypes([.rtf, .string, .pdf, .tiff], owner: nil)
        board.setData(Data("{\\rtf1 hi}".utf8), forType: .rtf)
        board.setString("hi", forType: .string)
        board.setData(Data("%PDF".utf8), forType: .pdf)
        board.setData(Data([0]), forType: .tiff)
        XCTAssertFalse(AttachmentPasteboard.hasAttachments(board))
    }

    func testCopiedPDFPagesAttachAsPDF() {
        let board = pasteboard()
        defer { board.releaseGlobally() }
        board.declareTypes([.pdf, .tiff, .string], owner: nil)
        board.setData(Data("%PDF".utf8), forType: .pdf)
        board.setData(Data([0]), forType: .tiff)
        board.setString("page text", forType: .string)
        XCTAssertEqual(AttachmentPasteboard.sources(from: board), [.data(Data("%PDF".utf8), filename: "Pasted PDF.pdf", typeIdentifier: UTType.pdf.identifier)])
    }
}

// MARK: - Requests

final class AttachmentRequestTests: XCTestCase {
    private func textAttachment(_ name: String, _ text: String) -> Attachment {
        .ready(filename: name, kind: .text, content: AttachmentContent(text: text, summary: "1 line"))
    }

    private func imageAttachment(_ name: String, _ data: Data) -> Attachment {
        .ready(filename: name, kind: .image, content: AttachmentContent(images: [data], summary: "PNG"))
    }

    func testTextAttachmentsPrecedeTheQuestion() throws {
        let message = ChatRequestBuilder.userMessage(text: "What does this do?", screens: [], attachments: [textAttachment("main.py", "print(1)")])
        guard case .text(let text) = message.content else { return XCTFail("Text-only attachments use a plain text message") }
        XCTAssertEqual(text, "<attachment name=\"main.py\">\nprint(1)\n</attachment>\n\nWhat does this do?")
    }

    func testImagePartsFollowScreensWithLabels() throws {
        let screen = Data([1]), photo = Data([2])
        let message = ChatRequestBuilder.userMessage(text: "Compare", screens: [screen], attachments: [imageAttachment("photo.heic", photo)])
        guard case .parts(let parts) = message.content else { return XCTFail("Expected multimodal parts") }
        let json = String(decoding: try JSONEncoder().encode(parts), as: UTF8.self)
        XCTAssertEqual(parts.count, 4)
        let order = ["\"Compare\"", screen.base64EncodedString(), "photo.heic", photo.base64EncodedString()].map { json.range(of: $0)!.lowerBound }
        XCTAssertEqual(order, order.sorted(), "Question, screen, label, then attachment image")
    }

    func testPDFSendsTextAndLabeledPageImages() throws {
        let pdf = Attachment.ready(filename: "paper.pdf", kind: .pdf, content: AttachmentContent(text: "[Page 1]\nAbstract", images: [Data([7]), Data([8])], pageCount: 12, summary: "12 pages"))
        let message = ChatRequestBuilder.userMessage(text: "Summarize", screens: [], attachments: [pdf])
        let json = String(decoding: try JSONEncoder().encode(ChatCompletionRequest(model: "m", messages: [message], stream: true)), as: UTF8.self)
        XCTAssertTrue(json.contains(#"type=\"pdf\" pages=\"12\""#))
        XCTAssertTrue(json.contains("Abstract"))
        XCTAssertTrue(json.contains("pages 1–2 of 12"))
        XCTAssertTrue(json.contains(Data([7]).base64EncodedString()) && json.contains(Data([8]).base64EncodedString()))
    }

    func testAttachmentOnlyMessageOmitsEmptyText() throws {
        let message = ChatRequestBuilder.userMessage(text: "", screens: [], attachments: [imageAttachment("a.png", Data([3]))])
        guard case .parts(let parts) = message.content else { return XCTFail() }
        let json = String(decoding: try JSONEncoder().encode(parts), as: UTF8.self)
        XCTAssertFalse(json.contains(#""text":"""#), "No empty text part")
    }

    func testHistoryKeepsAttachmentsAndSkipsUnreadyOnes() throws {
        let failed = Attachment(filename: "broken.bin", kind: .text, status: .failed("Not a text file"))
        let history = [ChatMessage(role: .user, content: "first", attachments: [textAttachment("a.txt", "alpha"), failed]), ChatMessage(role: .assistant, content: "ok")]
        let request = ChatRequestBuilder.messages(for: history, firstImage: nil, appendingUserText: "again")
        let json = String(decoding: try JSONEncoder().encode(ChatCompletionRequest(model: "m", messages: request, stream: true)), as: UTF8.self)
        XCTAssertTrue(json.contains("alpha"))
        XCTAssertFalse(json.contains("broken.bin"))
        guard case .text(let text) = request.last?.content else { return XCTFail() }
        XCTAssertEqual(text, "again", "Earlier attachments are not repeated on the new turn")
    }

    func testSystemPromptMentionsAttachments() {
        XCTAssertTrue(KKCopy.systemPrompt.contains("<attachment>"))
        XCTAssertTrue(KKCopy.systemPrompt.contains("may or may not be relevant"))
    }
}

// MARK: - Chat integration

final class AttachmentChatTests: XCTestCase {
    @MainActor
    private func makeChat() -> (ChatController, Preferences) {
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.baseURL = "https://fixture.invalid/v1"
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AttachmentRequestProtocol.self]
        let chat = ChatController(preferences: prefs, keychain: TestKeychain(), captureService: ScreenCaptureService(permissionCheck: { false }),
                                  apiClient: OpenAICompatibleClient(session: URLSession(configuration: config)))
        return (chat, prefs)
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition() && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition())
    }

    @MainActor
    func testAttachmentsLoadSendAndClear() async throws {
        let (chat, _) = makeChat()
        chat.addAttachments([.data(Data("SECRET-CONTENTS".utf8), filename: "notes.txt", typeIdentifier: UTType.plainText.identifier)])
        XCTAssertEqual(chat.pendingAttachments.count, 1)
        XCTAssertTrue(chat.pendingAttachments[0].isProcessing)
        XCTAssertFalse(chat.canSend, "Sending waits for attachments to finish loading")
        try await waitUntil { chat.pendingAttachments.first?.isReady == true }
        chat.prompt = "summarize"
        XCTAssertTrue(chat.canSend)
        AttachmentRequestProtocol.lastBody = nil
        chat.submit()
        XCTAssertTrue(chat.pendingAttachments.isEmpty)
        XCTAssertEqual(chat.messages.first?.attachments.map(\.filename), ["notes.txt"])
        try await waitUntil { !chat.isStreaming }
        XCTAssertTrue(AttachmentRequestProtocol.lastBody?.contains("SECRET-CONTENTS") == true)
        XCTAssertTrue(chat.clipboardTranscript.contains("_Attached: notes.txt"))
    }

    @MainActor
    func testAttachmentOnlySendFollowsPreference() async throws {
        let (chat, prefs) = makeChat()
        chat.addAttachments([.data(Data("x".utf8), filename: "a.txt", typeIdentifier: UTType.plainText.identifier)])
        try await waitUntil { chat.pendingAttachments.first?.isReady == true }
        XCTAssertTrue(prefs.allowAttachmentOnlySend, "On by default")
        XCTAssertTrue(chat.canSend)
        prefs.allowAttachmentOnlySend = false
        XCTAssertFalse(chat.canSend)
        prefs.allowAttachmentOnlySend = true
        chat.submit()
        XCTAssertEqual(chat.messages.first?.content, "")
        XCTAssertEqual(chat.messages.first?.attachments.count, 1)
        try await waitUntil { !chat.isStreaming }
    }

    @MainActor
    func testFailedAttachmentsDoNotBlockOrSend() async throws {
        let (chat, _) = makeChat()
        chat.addAttachments([.data(Data([0, 1, 2, 0, 0, 9]), filename: "blob.dat", typeIdentifier: UTType.data.identifier)])
        try await waitUntil { chat.pendingAttachments.first?.failureMessage != nil }
        XCTAssertFalse(chat.canSend, "A failed attachment alone isn't sendable")
        chat.prompt = "hi"
        XCTAssertTrue(chat.canSend)
        chat.submit()
        XCTAssertEqual(chat.messages.first?.attachments, [])
        try await waitUntil { !chat.isStreaming }
    }

    @MainActor
    func testRetryRestoresAttachmentsAndResetClearsThem() async throws {
        let (chat, _) = makeChat()
        chat.addAttachments([.data(Data("retry-me".utf8), filename: "r.txt", typeIdentifier: UTType.plainText.identifier)])
        try await waitUntil { chat.pendingAttachments.first?.isReady == true }
        chat.prompt = "go"
        chat.submit()
        try await waitUntil { !chat.isStreaming }
        AttachmentRequestProtocol.lastBody = nil
        chat.retry()
        try await waitUntil { !chat.isStreaming }
        XCTAssertEqual(chat.messages.filter { $0.role == .user }.count, 1)
        XCTAssertEqual(chat.messages.first?.attachments.map(\.filename), ["r.txt"])
        XCTAssertTrue(AttachmentRequestProtocol.lastBody?.contains("retry-me") == true)

        chat.addAttachments([.data(Data("x".utf8), filename: "b.txt", typeIdentifier: UTType.plainText.identifier)])
        chat.reset()
        XCTAssertTrue(chat.pendingAttachments.isEmpty)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(chat.pendingAttachments.isEmpty, "A load finishing after reset must not reappear")
    }

    @MainActor
    func testPerTurnLimitAndRemoval() async throws {
        let (chat, _) = makeChat()
        let sources = (0..<(AttachmentLimits.maxPerTurn + 2)).map { AttachmentSource.data(Data("\($0)".utf8), filename: "\($0).txt", typeIdentifier: UTType.plainText.identifier) }
        chat.addAttachments(sources)
        XCTAssertEqual(chat.pendingAttachments.count, AttachmentLimits.maxPerTurn)
        XCTAssertNotNil(chat.attachmentNotice)
        let first = try XCTUnwrap(chat.pendingAttachments.first?.id)
        chat.removeAttachment(first)
        XCTAssertEqual(chat.pendingAttachments.count, AttachmentLimits.maxPerTurn - 1)
        XCTAssertFalse(chat.pendingAttachments.contains { $0.id == first })
    }

    @MainActor
    func testPreferencesDefaultsAndReset() {
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        XCTAssertFalse(prefs.showAttachButton, "The attach button is hidden by default")
        XCTAssertTrue(prefs.allowAttachmentOnlySend)
        XCTAssertEqual(prefs.pdfPageImageLimit, AttachmentLimits.defaultPageImages)
        prefs.showAttachButton = true
        prefs.pdfPageImageLimit = 0
        prefs.allowAttachmentOnlySend = false
        prefs.popupMaterial = .translucent
        prefs.resetAdvanced()
        XCTAssertFalse(prefs.showAttachButton)
        XCTAssertTrue(prefs.allowAttachmentOnlySend)
        XCTAssertEqual(prefs.pdfPageImageLimit, AttachmentLimits.defaultPageImages)
        XCTAssertEqual(prefs.popupMaterial, .translucent, "Advanced reset leaves General settings alone")
    }
}

private final class AttachmentRequestProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var lastBody: String?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastBody = Self.body(of: request)
        let body = "data: {\"choices\":[{\"delta\":{\"content\":\"Done.\"}}]}\n\ndata: [DONE]\n\n"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    private static func body(of request: URLRequest) -> String? {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Rendering

final class AttachmentRenderTests: XCTestCase {
    /// Renders the attachment tray, drop feedback, and sent chips. Set KK_RENDER_DIR to save PNGs.
    @MainActor
    func testAttachmentStatesRender() async throws {
        _ = NSApplication.shared
        let prefs = Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        prefs.baseURL = "https://fixture.invalid/v1"
        prefs.onboardingComplete = true
        prefs.annotationsEnabled = false
        prefs.showAttachButton = true
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AttachmentRequestProtocol.self]
        let app = AppState(preferences: prefs, keychain: TestKeychain(), apiClient: OpenAICompatibleClient(session: URLSession(configuration: config)),
                           captureService: ScreenCaptureService(permissionCheck: { false }))
        app.togglePanel()
        defer { app.dismissPanel() }
        let panel = try XCTUnwrap(app.panelController.panel)
        XCTAssertNotNil(panel.attachmentDropHandler)
        app.chat.removeScreen()

        let image = try XCTUnwrap(AttachmentLoaderTests.makeImage(width: 400, height: 300, color: CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)))
        let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        app.chat.addAttachments([
            .data(png, filename: "IMG_2041.HEIC.png", typeIdentifier: UTType.png.identifier),
            .data(Data("import os\nprint(os.getcwd())\n".utf8), filename: "main.py", typeIdentifier: UTType.pythonScript.identifier),
            .data(try AttachmentLoaderTests.makeScannedPDF(text: "Quarterly report"), filename: "Quarterly report.pdf", typeIdentifier: UTType.pdf.identifier),
            .data(Data([0, 1, 0, 2, 0, 0]), filename: "archive.bin", typeIdentifier: UTType.data.identifier)
        ])
        try await render(panel, "attachments-loading")
        let deadline = ContinuousClock.now.advanced(by: .seconds(60))
        while app.chat.hasProcessingAttachments && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(app.chat.hasProcessingAttachments)
        try await render(panel, "attachments-ready")

        app.chat.isDropTargeted = true
        try await render(panel, "attachments-drop-target")
        XCTAssertFalse(app.dismissShortDraftWouldClose, "Pending attachments keep the popup open")
        app.chat.isDropTargeted = false

        app.chat.prompt = "What's in these?"
        app.chat.submit()
        let done = ContinuousClock.now.advanced(by: .seconds(5))
        while app.chat.isStreaming && ContinuousClock.now < done { try await Task.sleep(for: .milliseconds(50)) }
        try await render(panel, "attachments-sent")
        app.chat.isDropTargeted = true
        try await render(panel, "attachments-drop-target-followup")
        app.chat.isDropTargeted = false
    }

    @MainActor
    private func render(_ panel: NSWindow, _ name: String) async throws {
        try await Task.sleep(for: .milliseconds(400))
        let view = try XCTUnwrap(panel.contentView)
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        guard let directory = ProcessInfo.processInfo.environment["KK_RENDER_DIR"] else { return }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }
}
