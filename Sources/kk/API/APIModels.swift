import Foundation

struct ChatCompletionRequest: Encodable, Sendable {
    let model: String
    let messages: [APIMessage]
    let stream: Bool
    var responseFormat: ResponseFormat? = nil

    private enum CodingKeys: String, CodingKey {
        case model, messages, stream
        case responseFormat = "response_format"
    }

    struct ResponseFormat: Encodable, Sendable {
        let type: String
        static let jsonObject = Self(type: "json_object")
    }
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
        let delta: AssistantDelta
    }

    let choices: [Choice]
}

struct CompletionResponse: Decodable {
    struct Choice: Decodable {
        let message: AssistantDelta
    }

    let choices: [Choice]
}

enum CompletionDelta: Equatable, Sendable {
    case content(String)
    case reasoning(String)
}

struct AssistantDelta: Decodable {
    let content: String?
    let reasoning: String?

    private enum CodingKeys: String, CodingKey {
        case content, reasoning
        case reasoningContent = "reasoning_content"
        case reasoningDetails = "reasoning_details"
    }
    private struct ReasoningDetail: Decodable {
        let type: String?
        let text: String?
        let summary: String?
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        content = try? values.decodeIfPresent(String.self, forKey: .content)
        let direct = (try? values.decodeIfPresent(String.self, forKey: .reasoningContent))
            ?? (try? values.decodeIfPresent(String.self, forKey: .reasoning))
        let details = (try? values.decodeIfPresent([ReasoningDetail].self, forKey: .reasoningDetails)) ?? []
        let text = details.compactMap { detail -> String? in
            switch detail.type {
            case "reasoning.text": detail.text
            case "reasoning.summary": detail.summary
            default: nil // Encrypted/redacted blocks are not displayable thinking.
            }
        }.joined()
        reasoning = direct?.isEmpty == false ? direct : (text.isEmpty ? nil : text)
    }
}

struct APIErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError?
}
