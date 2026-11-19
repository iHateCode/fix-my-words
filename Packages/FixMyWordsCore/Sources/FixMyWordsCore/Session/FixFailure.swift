/// An error turned into the message and button the preview panel shows.
/// OpenRouter's own message is plain text: show it as-is, never as formatted or clickable content.
public struct FixFailure: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case openSettings
        case openOpenRouter           // https://openrouter.ai/settings/credits
        case openSystemSettings       // the Accessibility page of Privacy & Security
        case retry
    }

    public let message: String
    public let action: Action?        // nil: no button, and the panel closes after 2 s

    public init(_ error: Error) {
        switch error {
        case AIError.noKey:
            (message, action) = ("No OpenRouter key yet.", .openSettings)
        case AIError.unauthorized:
            (message, action) = ("OpenRouter didn't accept your key.", .openSettings)
        case AIError.outOfCredit:
            (message, action) = ("Your OpenRouter credit or spending limit has run out.", .openOpenRouter)
        case AIError.badRequest(let reason), AIError.blocked(let reason):
            (message, action) = (reason.isEmpty ? "OpenRouter refused this request."
                                                : "OpenRouter refused this request: \(reason)", .openSettings)
        case AIError.rateLimited, AIError.server, AIError.network, AIError.emptyAnswer,
             AIError.incomplete, AIError.badResponse:
            (message, action) = ("OpenRouter didn't answer.", .retry)
        case AIError.timedOut:
            (message, action) = ("OpenRouter took longer than 60 seconds.", .retry)
        case CaptureError.noPermission:
            (message, action) = ("Fix My Words needs Accessibility permission.", .openSystemSettings)
        case CaptureError.nothingSelected, CaptureError.copyTimedOut:
            (message, action) = ("Select some text first.", nil)
        default:
            (message, action) = ("Something went wrong.", .retry)
        }
    }
}
