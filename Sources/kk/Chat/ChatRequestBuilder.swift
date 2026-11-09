import Foundation

enum ChatRequestBuilder {
    static func messages(
        for chatMessages: [ChatMessage],
        firstImage: Data?,
        appendingUserText: String? = nil,
        appendingImage: Data? = nil,
        additionalImages: [Data] = [],
        appendingAttachments: [Attachment] = []
    ) -> [APIMessage] {
        var result = [APIMessage(role: "system", content: .text(KKCopy.systemPrompt))]
        var image = firstImage

        for message in chatMessages {
            if message.role == .user {
                let screens = (message.screenData ?? image).map { [$0] + message.additionalScreenData } ?? []
                if !screens.isEmpty { image = nil }
                result.append(userMessage(text: message.content, screens: screens, attachments: message.attachments))
            } else {
                result.append(APIMessage(role: message.role.rawValue, content: .text(message.content)))
            }
        }

        if let appendingUserText {
            let screens = (appendingImage ?? image).map { [$0] + additionalImages } ?? []
            result.append(userMessage(text: appendingUserText, screens: screens, attachments: appendingAttachments))
        }

        return result
    }

    static func userMessage(text: String, screens: [Data], attachments: [Attachment]) -> APIMessage {
        let ready = attachments.filter(\.isReady)
        let prompt = composedText(question: text, attachments: ready)
        let attachmentImages = ready.filter { !($0.content?.images.isEmpty ?? true) }
        guard !screens.isEmpty || !attachmentImages.isEmpty else {
            return APIMessage(role: "user", content: .text(prompt))
        }
        var parts: [ContentPart] = prompt.isEmpty ? [] : [.text(prompt)]
        parts += screens.map(imagePart)
        for attachment in attachmentImages {
            guard let content = attachment.content else { continue }
            parts.append(.text(imageLabel(for: attachment, content: content)))
            parts += content.images.map(imagePart)
        }
        return APIMessage(role: "user", content: .parts(parts))
    }

    /// Text attachments come before the question, so the question reads as the final instruction.
    static func composedText(question: String, attachments: [Attachment]) -> String {
        let blocks = attachments.compactMap { attachment -> String? in
            guard let content = attachment.content else { return nil }
            let name = attributeValue(attachment.filename)
            switch attachment.kind {
            case .image:
                return nil
            case .text:
                var block = "<attachment name=\"\(name)\">\n\(content.text ?? "")\n</attachment>"
                if content.truncated { block += "\n(The attachment above was truncated to its first \(AttachmentLimits.maxTextCharacters) characters.)" }
                return block
            case .pdf:
                var attributes = "name=\"\(name)\" type=\"pdf\""
                if let pages = content.pageCount { attributes += " pages=\"\(pages)\"" }
                var block = "<attachment \(attributes)>\n\(content.text ?? "")\n</attachment>"
                if content.truncated { block += "\n(The PDF text above is incomplete because the document is too long.)" }
                return block
            }
        }
        return (blocks + [question]).filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    static func imageLabel(for attachment: Attachment, content: AttachmentContent) -> String {
        let name = attributeValue(attachment.filename)
        switch attachment.kind {
        case .pdf:
            let total = content.pageCount ?? content.images.count
            let range = content.images.count == 1 ? "page 1" : "pages 1–\(content.images.count)"
            return "<attachment-images name=\"\(name)\">Images of \(range) of \(total) from this PDF follow.</attachment-images>"
        default:
            return "<attachment-image name=\"\(name)\" />"
        }
    }

    private static func imagePart(_ data: Data) -> ContentPart {
        .imageURL("data:image/jpeg;base64,\(data.base64EncodedString())")
    }

    private static func attributeValue(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "'").replacingOccurrences(of: "\n", with: " ")
    }
}
