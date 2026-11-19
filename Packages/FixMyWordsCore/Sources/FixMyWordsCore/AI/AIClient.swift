/// One model and its own thinking level.
public struct ModelChoice: Codable, Equatable, Sendable {
    public var id: String          // OpenRouter model id, e.g. "openai/gpt-6-luna"
    public var effort: String?     // OpenRouter `reasoning.effort`; nil = send no `reasoning` field
    public init(id: String, effort: String?) { self.id = id; self.effort = effort }
}

public protocol AIClient: Sendable {
    /// Streams the answer text piece by piece, from one model. Throws `AIError`.
    /// The stream finishes without error only when the model said it finished normally.
    func fix(text: String, instruction: String, model: ModelChoice) -> AsyncThrowingStream<String, Error>
}

public enum AIError: Error, Equatable {
    case noKey
    case unauthorized             // 401: bad or revoked key
    case outOfCredit              // 402: no credit or spending limit reached
    case badRequest(String)       // 400 / 404: e.g. retired model id, unsupported thinking level
    case blocked(String)          // 403: moderation flag or guardrail
    case rateLimited              // 429
    case server(Int)              // 5xx and any other status
    case timedOut                 // 408, or our 60-second whole-request deadline
    case network
    case emptyAnswer              // finished with no text
    case incomplete               // stream ended without finish_reason "stop" (error, length limit, disconnect)
    case badResponse              // a stream line we couldn't decode

    /// Maps an OpenRouter error code (HTTP status, or `error.code` inside a stream) to an `AIError`.
    /// `message` is OpenRouter's `error.message`: untrusted text, shown as plain text only, cut to 200 characters.
    static func from(code: Int, message: String?) -> AIError {
        let reason = String((message ?? "").prefix(200))
        switch code {
        case 400, 404: return .badRequest(reason)
        case 401: return .unauthorized
        case 402: return .outOfCredit
        case 403: return .blocked(reason)
        case 408: return .timedOut
        case 429: return .rateLimited
        default: return .server(code)
        }
    }
}
