import Foundation

struct OpenAICompatibleClient: Sendable {
    func streamCompletion(
        request: ChatCompletionRequest,
        configuration: APIConfiguration
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let validated = try configuration.validated()
                    let urlRequest = try makeURLRequest(request: request, configuration: validated)
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
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
                    var finished = false

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        rawLines.append(line)
                        let events = parser.consume(line: line)
                        for event in events {
                            if event == "[DONE]" {
                                finished = true
                                break
                            }
                            let emitted = try emit(event: event, continuation: continuation)
                            emittedContent = emittedContent || emitted
                        }
                        if finished { break }
                    }

                    if !finished {
                        for event in parser.finish() {
                            if event == "[DONE]" {
                                finished = true
                            } else {
                                let emitted = try emit(event: event, continuation: continuation)
                                emittedContent = emittedContent || emitted
                            }
                        }
                    }

                    if !emittedContent {
                        let rawData = Data(rawLines.joined(separator: "\n").utf8)
                        if let completion = try? JSONDecoder().decode(CompletionResponse.self, from: rawData),
                           let content = completion.choices.first?.message.content,
                           !content.isEmpty {
                            continuation.yield(content)
                        } else if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: rawData),
                                  let message = apiError.error?.message {
                            throw KKError.streamFailed(message)
                        }
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
        result.httpBody = try JSONEncoder().encode(request)
        return result
    }

    private func emit(event: String, continuation: AsyncThrowingStream<String, Error>.Continuation) throws -> Bool {
        guard let data = event.data(using: .utf8) else { return false }

        if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data),
           let message = apiError.error?.message {
            throw KKError.streamFailed(message)
        }

        guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
              let content = chunk.choices.first?.delta.content,
              !content.isEmpty else { return false }
        continuation.yield(content)
        return true
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
