import Foundation

enum InferenceParameters {
    static let efforts = ["none", "minimal", "low", "medium", "high", "xhigh"]
    static let reserved: Set<String> = ["model", "messages", "stream", "response_format"]

    static func parse(_ text: String) throws -> [String: Any] {
        let source = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty else { return [:] }
        let json = try JSONSerialization.jsonObject(with: Data(source.utf8), options: [.fragmentsAllowed])
        guard let object = json as? [String: Any] else {
            throw ValidationError(message: "Enter a JSON object, such as {\"temperature\": 0.7}.")
        }
        let conflicts = object.keys.filter { reserved.contains($0) }.sorted()
        guard conflicts.isEmpty else {
            throw ValidationError(message: "kk manages these parameters: \(conflicts.joined(separator: ", ")).")
        }
        guard !object.keys.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ValidationError(message: "Parameter names can't be empty.")
        }
        return object
    }

    static func validationMessage(_ text: String) -> String? {
        do { _ = try parse(text); return nil }
        catch { return error.localizedDescription }
    }

    struct ValidationError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
