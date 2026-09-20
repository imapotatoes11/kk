import Foundation

struct SSEParser: Sendable {
    private var dataLines: [String] = []

    mutating func consume(line: String) -> [String] {
        if line.isEmpty {
            return flushEvent()
        }
        guard !line.hasPrefix(":") else { return [] }

        if line.hasPrefix("data:") {
            var value = String(line.dropFirst(5))
            if value.first == " " { value.removeFirst() }
            dataLines.append(value)
        }
        return []
    }

    mutating func finish() -> [String] {
        flushEvent()
    }

    private mutating func flushEvent() -> [String] {
        defer { dataLines.removeAll(keepingCapacity: true) }
        guard !dataLines.isEmpty else { return [] }
        return [dataLines.joined(separator: "\n")]
    }
}
