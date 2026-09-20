enum GenerationState {
    case idle
    case streaming
    case completed
    case error(KKError)

    var isStreaming: Bool {
        if case .streaming = self { return true }
        return false
    }
}
