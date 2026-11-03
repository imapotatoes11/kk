import Foundation

enum ChatRequestBuilder {
    static func messages(
        for chatMessages: [ChatMessage],
        firstImage: Data?,
        appendingUserText: String? = nil,
        appendingImage: Data? = nil,
        additionalImages: [Data] = []
    ) -> [APIMessage] {
        var result = [APIMessage(role: "system", content: .text(KKCopy.systemPrompt))]
        var image = firstImage

        for message in chatMessages {
            if message.role == .user, let imageData = message.screenData ?? image {
                result.append(multimodalUserMessage(text: message.content, images: [imageData] + message.additionalScreenData))
                image = nil
            } else {
                result.append(APIMessage(role: message.role.rawValue, content: .text(message.content)))
            }
        }

        if let appendingUserText {
            if let imageData = appendingImage ?? image {
                result.append(multimodalUserMessage(text: appendingUserText, images: [imageData] + additionalImages))
            } else {
                result.append(APIMessage(role: "user", content: .text(appendingUserText)))
            }
        }

        return result
    }

    private static func multimodalUserMessage(text: String, images: [Data]) -> APIMessage {
        APIMessage(role: "user", content: .parts([.text(text)] + images.map {
            .imageURL("data:image/jpeg;base64,\($0.base64EncodedString())")
        }))
    }
}
