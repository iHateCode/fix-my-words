import Foundation

public struct OpenRouterClient: AIClient {
    public struct Settings: Equatable, Sendable {
        public var primary = ModelChoice(id: "openai/gpt-6-luna", effort: "none")
        public var backup = ModelChoice(id: "google/gemini-3.8-flash", effort: "low")    // backup when the main model fails
        public var baseURL = URL(string: "https://openrouter.ai/api/v1")!   // overridden in UI tests
        public var timeout: TimeInterval = 60        // whole request, keep-alives included
        public var idleTimeout: TimeInterval = 20    // no bytes at all, not even a keep-alive
        public init() {}
    }

    public let settings: Settings
    let keyProvider: @Sendable () -> String?
    let session: URLSession

    public init(settings: Settings, keyProvider: @escaping @Sendable () -> String?, session: URLSession? = nil) {
        self.settings = settings; self.keyProvider = keyProvider
        self.session = session ?? URLSession(configuration: Self.configuration(settings))
    }

    /// `URLRequest.timeoutInterval` only counts idle time, and keep-alives reset it.
    /// `timeoutIntervalForResource` counts the whole request.
    static func configuration(_ settings: Settings) -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral            // no cookies or cache on disk
        config.timeoutIntervalForRequest = settings.idleTimeout
        config.timeoutIntervalForResource = settings.timeout
        return config
    }

    /// Called by the coordinator when it replaces this client after a Settings change.
    public func invalidate() { session.finishTasksAndInvalidate() }

    public func fix(text: String, instruction: String, model: ModelChoice) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let key = keyProvider(), !key.isEmpty else { throw AIError.noKey }
                    let request = try makeRequest(key: key, text: text, instruction: instruction, model: model)
                    let (bytes, response) = try await session.bytes(for: request)
                    try await Self.check(response, body: bytes)
                    var gotText = false
                    var finishReason: String?
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }   // skips ": OPENROUTER PROCESSING" keep-alives
                        let payload = line.dropFirst(6)
                        if payload == "[DONE]" { break }
                        guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: Data(payload.utf8)) else {
                            throw AIError.badResponse
                        }
                        // A mid-stream error arrives with HTTP 200, as a chunk carrying `error` (OpenRouter errors docs).
                        if let error = chunk.error { throw AIError.from(code: error.code, message: error.message) }
                        guard let choice = chunk.choices?.first else { continue }   // the final usage chunk has no choices
                        if let piece = choice.delta?.content, !piece.isEmpty {
                            gotText = true
                            continuation.yield(piece)
                        }
                        if let reason = choice.finishReason { finishReason = reason }
                    }
                    guard gotText else { throw AIError.emptyAnswer }
                    guard finishReason == "stop" else { throw AIError.incomplete }   // "length", "error", or cut off
                    continuation.finish()
                } catch let error as URLError where error.code == .timedOut {
                    continuation.finish(throwing: AIError.timedOut)
                } catch is URLError {
                    continuation.finish(throwing: AIError.network)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }    // Cancel button and Esc really cancel
        }
    }

    func makeRequest(key: String, text: String, instruction: String, model: ModelChoice) throws -> URLRequest {
        var request = URLRequest(url: settings.baseURL.appending(path: "chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://github.com/iHateCode/fix-my-words", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Fix My Words", forHTTPHeaderField: "X-Title")
        let body = ChatRequest(
            model: model.id,
            messages: PromptBuilder.messages(text: text, instruction: instruction),
            stream: true,
            reasoning: model.effort.map { .init(effort: $0) })
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    /// Returns for 200. Otherwise reads at most 8 KB of the error body for OpenRouter's message, then throws.
    static func check(_ response: URLResponse, body: URLSession.AsyncBytes) async throws {
        guard let http = response as? HTTPURLResponse else { throw AIError.network }
        guard http.statusCode != 200 else { return }
        var data = Data()
        for try await byte in body {
            data.append(byte)
            if data.count >= 8_192 { break }
        }
        let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.message
        throw AIError.from(code: http.statusCode, message: message)
    }
}

struct ChatRequest: Encodable {
    struct Reasoning: Encodable { let effort: String }
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let reasoning: Reasoning?      // left out of the JSON when nil
}

struct ChatMessage: Encodable { let role: String; let content: String }

struct OpenRouterError: Decodable { let code: Int; let message: String? }
struct ErrorBody: Decodable { let error: OpenRouterError }

struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable { let content: String? }
        let delta: Delta?
        let finishReason: String?
        enum CodingKeys: String, CodingKey { case delta, finishReason = "finish_reason" }
    }
    let choices: [Choice]?
    let error: OpenRouterError?
}
