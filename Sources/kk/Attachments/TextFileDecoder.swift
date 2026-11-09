import Foundation

/// Decodes text files written by common editors on macOS, Linux, and Windows: UTF-8 (with or
/// without a byte-order mark), UTF-16 and UTF-32 in either byte order, and Windows-1252.
enum TextFileDecoder {
    struct Result: Equatable {
        let text: String
        let encoding: String.Encoding
    }

    static func decode(_ data: Data) throws -> Result {
        if data.isEmpty { return Result(text: "", encoding: .utf8) }
        let bytes = [UInt8](data.prefix(4))

        // A byte-order mark is authoritative. Check UTF-32 before UTF-16 because FF FE 00 00
        // also starts with the UTF-16 little-endian mark.
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { return try finish(data.dropFirst(3), .utf8) }
        if bytes.starts(with: [0xFF, 0xFE, 0x00, 0x00]) { return try finish(data.dropFirst(4), .utf32LittleEndian) }
        if bytes.starts(with: [0x00, 0x00, 0xFE, 0xFF]) { return try finish(data.dropFirst(4), .utf32BigEndian) }
        if bytes.starts(with: [0xFF, 0xFE]) { return try finish(data.dropFirst(2), .utf16LittleEndian) }
        if bytes.starts(with: [0xFE, 0xFF]) { return try finish(data.dropFirst(2), .utf16BigEndian) }

        if let utf16 = guessUTF16WithoutBOM(data) { return try finish(data, utf16) }
        if let text = String(data: data, encoding: .utf8) { return try validated(text, .utf8) }
        // NUL bytes in a file that isn't UTF-16 or UTF-32 mean the file is binary.
        if data.contains(0) { throw AttachmentError.binaryFile }
        if let text = String(data: data, encoding: .windowsCP1252) { return try validated(text, .windowsCP1252) }
        throw AttachmentError.binaryFile
    }

    /// Windows tools such as PowerShell's `Out-File` and older Notepad versions can write
    /// UTF-16 without a byte-order mark. ASCII-heavy text then has a NUL in every other byte.
    static func guessUTF16WithoutBOM(_ data: Data) -> String.Encoding? {
        let sample = [UInt8](data.prefix(4096))
        guard sample.count >= 4 else { return nil }
        var evenZeros = 0, oddZeros = 0
        for (index, byte) in sample.enumerated() where byte == 0 {
            if index.isMultiple(of: 2) { evenZeros += 1 } else { oddZeros += 1 }
        }
        let half = Double(sample.count) / 2
        if Double(oddZeros) / half > 0.3 && Double(evenZeros) / half < 0.05 { return .utf16LittleEndian }
        if Double(evenZeros) / half > 0.3 && Double(oddZeros) / half < 0.05 { return .utf16BigEndian }
        return nil
    }

    private static func finish(_ data: Data, _ encoding: String.Encoding) throws -> Result {
        guard let text = String(data: data, encoding: encoding) else { throw AttachmentError.binaryFile }
        return try validated(text, encoding)
    }

    private static func validated(_ raw: String, _ encoding: String.Encoding) throws -> Result {
        var text = raw
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        guard !looksBinary(text) else { throw AttachmentError.binaryFile }
        return Result(text: text, encoding: encoding)
    }

    /// Text files rarely contain control characters other than tab, newline, and form feed.
    static func looksBinary(_ text: String) -> Bool {
        var control = 0, total = 0
        for scalar in text.unicodeScalars.prefix(65_536) {
            total += 1
            if scalar.value == 0 { return true }
            if scalar.value < 0x20 && ![0x09, 0x0A, 0x0C, 0x0D].contains(scalar.value) { control += 1 }
        }
        return total > 0 && Double(control) / Double(total) > 0.01
    }
}
