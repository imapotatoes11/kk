import Foundation

struct ChatCompletionRequest: Encodable, Sendable {
    let model: String
    let messages: [APIMessage]
    let stream: Bool
}

struct APIMessage: Encodable, Sendable {
    let role: String
    let content: MessageContent
}

enum MessageContent: Encodable, Sendable {
    case text(String)
    case parts([ContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value):
            try container.encode(value)
        case .parts(let parts):
            try container.encode(parts)
        }
    }
}

enum ContentPart: Encodable, Sendable {
    case text(String)
    case imageURL(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case .imageURL(let value):
            try container.encode("image_url", forKey: .type)
            try container.encode(["url": value], forKey: .imageURL)
        }
    }
}

struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }

        let delta: Delta
    }

    let choices: [Choice]
}

struct CompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message
    }

    let choices: [Choice]
}

struct APIErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError?
}
