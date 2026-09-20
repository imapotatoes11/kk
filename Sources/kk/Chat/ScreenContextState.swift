import Foundation

enum ScreenContextState {
    case capturing
    case ready(Data)
    case disabled
    case permissionRequired
    case failed(String)
    case sent(Data)

    var previewData: Data? {
        switch self {
        case .ready(let data), .sent(let data): data
        default: nil
        }
    }

    var label: String {
        switch self {
        case .capturing: "Capturing screen…"
        case .ready: "Screen attached"
        case .disabled: "No screen attached"
        case .permissionRequired: "Screen access needed"
        case .failed: "Screen unavailable"
        case .sent: "Screen sent"
        }
    }
}
