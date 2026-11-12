import Foundation

struct OpenAICompatibleClient: Sendable {
    var session: URLSession = .shared

    func streamCompletion(
        request: ChatCompletionRequest,
        configuration: APIConfiguration
    ) -> AsyncThrowingStream<CompletionDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var config = configuration
                // Explicit JSON overrides remain authoritative, including null.
                let customReasoning = (try? InferenceParameters.parse(config.customParameters))?.keys.contains("reasoning_effort") == true
                if customReasoning {
                    config.reasoningEffort = nil
                    config.retryWithoutReasoning = false
                } else if let policy = config.reasoningPolicy {
                    let attempt = await policy()
                    config.reasoningEffort = attempt.effort
                    config.retryWithoutReasoning = attempt.trial
                }
                var emitted = false
                do {
                    do {
                        for try await delta in streamOnce(request: request, configuration: config) {
                            emitted = true
                            continuation.yield(delta)
                        }
                    } catch {
                        // Only retry server/response errors before any output. Cancellation,
                        // transport failures and partial answers must never duplicate a request.
                        let responseError: Bool
                        switch error as? KKError {
                        case .server, .unauthorized, .rateLimited, .streamFailed, .invalidResponse: responseError = true
                        default: responseError = false
                        }
                        guard responseError, !Task.isCancelled, !emitted,
                              config.retryWithoutReasoning, config.reasoningEffort != nil else { throw error }
                        await config.onReasoningFailure?()
                        try Task.checkCancellation()
                        config.reasoningEffort = nil
                        for try await delta in streamOnce(request: request, configuration: config) {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func streamOnce(
        request: ChatCompletionRequest,
        configuration: APIConfiguration
    ) -> AsyncThrowingStream<CompletionDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let validated = try configuration.validated()
                    let urlRequest = try makeURLRequest(request: request, configuration: validated)
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw KKError.invalidResponse
                    }

                    if !(200..<300).contains(httpResponse.statusCode) {
                        let body = try await collect(bytes)
                        throw serverError(status: httpResponse.statusCode, body: body)
                    }

                    var parser = SSEParser()
                    var rawLines: [String] = []
                    var emittedContent = false
                    var emittedAnswer = false
                    var finished = false

                    func consumeLine(_ line: String) throws {
                        rawLines.append(line)
                        let events = parser.consume(line: line)
                        for event in events {
                            if event == "[DONE]" {
                                finished = true
                                break
                            }
                            let emitted = try emit(event: event, continuation: continuation)
                            emittedContent = emittedContent || emitted.any
                            emittedAnswer = emittedAnswer || emitted.answer
                        }
                    }

                    // AsyncBytes.lines omits empty lines on macOS, but SSE uses
                    // them to delimit events. Split the bytes explicitly.
                    var lineBytes: [UInt8] = []
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        if byte == 10 {
                            if lineBytes.last == 13 { lineBytes.removeLast() }
                            try consumeLine(String(decoding: lineBytes, as: UTF8.self))
                            lineBytes.removeAll(keepingCapacity: true)
                            if finished { break }
                        } else {
                            lineBytes.append(byte)
                        }
                    }
                    if !finished && !lineBytes.isEmpty {
                        if lineBytes.last == 13 { lineBytes.removeLast() }
                        try consumeLine(String(decoding: lineBytes, as: UTF8.self))
                    }

                    if !finished {
                        for event in parser.finish() {
                            if event == "[DONE]" {
                                finished = true
                            } else {
                                let emitted = try emit(event: event, continuation: continuation)
                                emittedContent = emittedContent || emitted.any
                                emittedAnswer = emittedAnswer || emitted.answer
                            }
                        }
                    }

                    if emittedContent && !finished {
                        throw KKError.streamFailed("The connection ended before the answer was complete. Please retry.")
                    }
                    if !emittedContent {
                        let rawData = Data(rawLines.joined(separator: "\n").utf8)
                        if let completion = try? JSONDecoder().decode(CompletionResponse.self, from: rawData),
                           let content = completion.choices.first?.message.content,
                           !content.isEmpty {
                            if let reasoning = completion.choices.first?.message.reasoning, !reasoning.isEmpty {
                                continuation.yield(.reasoning(reasoning))
                            }
                            continuation.yield(.content(content))
                            emittedAnswer = true
                        } else if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: rawData),
                                  let message = apiError.error?.message {
                            throw KKError.streamFailed(message)
                        } else {
                            throw KKError.invalidResponse
                        }
                    }

                    guard emittedAnswer else {
                        throw KKError.streamFailed("The provider returned thinking without an answer. Please retry.")
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func makeURLRequest(
        request: ChatCompletionRequest,
        configuration: APIConfiguration
    ) throws -> URLRequest {
        let configuration = try configuration.validated()
        guard let url = configuration.endpointURL else { throw KKError.invalidBaseURL }

        var result = URLRequest(url: url)
        result.httpMethod = "POST"
        result.setValue("application/json", forHTTPHeaderField: "Content-Type")
        result.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if !configuration.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            result.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        }
        var body = try InferenceParameters.parse(configuration.customParameters)
        let core = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as! [String: Any]
        body.merge(core) { _, core in core }
        if body["reasoning_effort"] == nil, let effort = configuration.reasoningEffort {
            body["reasoning_effort"] = effort
        }
        result.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        return result
    }

    private func emit(event: String, continuation: AsyncThrowingStream<CompletionDelta, Error>.Continuation) throws -> (any: Bool, answer: Bool) {
        guard let data = event.data(using: .utf8) else { return (false, false) }
        if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
           let message = apiError.error?.message {
            throw KKError.streamFailed(message)
        }
        guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
              let delta = chunk.choices.first?.delta else { return (false, false) }
        var emitted = false
        if let reasoning = delta.reasoning, !reasoning.isEmpty {
            continuation.yield(.reasoning(reasoning))
            emitted = true
        }
        if let content = delta.content, !content.isEmpty {
            continuation.yield(.content(content))
            return (true, true)
        }
        return (emitted, false)
    }

    private func collect(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    private func serverError(status: Int, body: Data) -> KKError {
        let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: body))?.error?.message
        switch status {
        case 401, 403: return .unauthorized
        case 429: return .rateLimited
        default: return .server(status: status, message: message)
        }
    }
}
