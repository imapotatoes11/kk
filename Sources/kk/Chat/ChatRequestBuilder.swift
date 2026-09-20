import Foundation

enum ChatRequestBuilder {
    static func messages(
        for chatMessages: [ChatMessage],
        firstImage: Data?,
        appendingUserText: String? = nil
    ) -> [APIMessage] {
        var result = [APIMessage(role: "system", content: .text(KKCopy.systemPrompt))]
        var image = firstImage

        for message in chatMessages {
            if message.role == .user, let imageData = image {
                result.append(multimodalUserMessage(text: message.content, imageData: imageData))
                image = nil
            } else {
                result.append(APIMessage(role: message.role.rawValue, content: .text(message.content)))
            }
        }

        if let appendingUserText {
            if let imageData = image {
                result.append(multimodalUserMessage(text: appendingUserText, imageData: imageData))
            } else {
                result.append(APIMessage(role: "user", content: .text(appendingUserText)))
            }
        }

        return result
    }

    private static func multimodalUserMessage(text: String, imageData: Data) -> APIMessage {
        APIMessage(role: "user", content: .parts([
            .text(text),
            .imageURL("data:image/jpeg;base64,\(imageData.base64EncodedString())")
        ]))
    }
}
