import Foundation

enum KKError: LocalizedError, Equatable {
    case missingAPIKey
    case invalidBaseURL
    case invalidModel
    case screenCapturePermission
    case screenCaptureFailed(String)
    case network(String)
    case unauthorized
    case rateLimited
    case server(status: Int, message: String?)
    case invalidResponse
    case streamFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "The API rejected your credentials."
        case .invalidBaseURL, .invalidModel:
            "Finish API setup before sending."
        case .screenCapturePermission:
            "kk needs Screen Recording access to see your screen."
        case .screenCaptureFailed(let reason):
            reason
        case .network:
            "Couldn't reach the API."
        case .unauthorized:
            "The API rejected your credentials."
        case .rateLimited:
            "The API rate limit was reached."
        case .server:
            "The provider returned an error."
        case .invalidResponse:
            "The provider returned an invalid response."
        case .streamFailed(let reason):
            reason
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .missingAPIKey, .unauthorized:
            "Check your API key in Settings."
        case .invalidBaseURL, .invalidModel:
            "Open Settings to correct the endpoint or model."
        case .rateLimited:
            "Try again in a moment."
        case .network:
            "Check your connection and Base URL."
        case .screenCapturePermission:
            "Grant Screen Recording access in System Settings, or continue without a screen."
        case .server(_, let message):
            message
        case .streamFailed(let message):
            message
        default:
            nil
        }
    }
}
