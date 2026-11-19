import AppKit
import Observation

@MainActor @Observable
public final class FixSession {
    public enum State: Equatable {
        case streaming(partial: String)
        case review(original: String, result: String, diff: [DiffSpan], usedBackup: Bool)
        case noChanges
        case failed(FixFailure)
        case pasteRefused(result: String)
        case done
    }

    public private(set) var state: State = .streaming(partial: "")
    public let capture: Capture
    public let command: Command
    private let ai: any AIClient
    private let primary: ModelChoice
    private let backup: ModelChoice
    private let text: any TextAccess
    private let history: HistoryStore
    private let edges: PromptBuilder.Edges      // the selection split into leading space, text to fix, trailing space
    private var task: Task<Void, Never>?
    /// Set by the panel. Called before every paste, reviewed or instant, so the panel can hide and hand the
    /// keyboard back to the target app; otherwise the posted ⌘V lands in the panel.
    public var willPaste: (@MainActor () async -> Void)?
    /// Set by the panel, to show itself again when the paste guard refuses.
    public var pasteWasRefused: (@MainActor () -> Void)?

    public init(capture: Capture, command: Command, ai: any AIClient, primary: ModelChoice, backup: ModelChoice,
                text: any TextAccess, history: HistoryStore) {
        self.capture = capture; self.command = command; self.ai = ai
        self.primary = primary; self.backup = backup; self.text = text; self.history = history
        edges = PromptBuilder.splitEdges(capture.text)
    }

    public func start() {
        task = Task { await run(quietRetry: true) }
    }

    /// Main model, one quiet retry of it, then the backup.
    private func run(quietRetry: Bool) async {
        var model = primary
        var retriedPrimary = !quietRetry
        while true {
            do {
                try await attempt(with: model)
                return
            } catch {
                if Task.isCancelled { return }                  // Cancel/Esc: ignore the error it causes
                let next = (error as? AIError)?.next ?? .stop
                if model == primary, next == .retry, !retriedPrimary {
                    retriedPrimary = true
                } else if model == primary, next != .stop, backup != primary {
                    model = backup
                } else {
                    state = .failed(FixFailure(error))
                    return
                }
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }                  // cancelled during the pause: don't start another attempt
            }
        }
    }

    private func attempt(with model: ModelChoice) async throws {
        state = .streaming(partial: "")                         // drops partial text from a failed attempt
        var answer = ""
        for try await piece in ai.fix(text: edges.core, instruction: command.instruction, model: model) {
            answer += piece
            state = .streaming(partial: answer)
        }
        if Task.isCancelled { return }

        let fixed = PromptBuilder.cleanIfSafe(answer, original: edges.core)
        if fixed == edges.core { state = .noChanges; return }
        let result = edges.lead + fixed + edges.trail           // keep the surrounding spaces and line breaks
        if command.applyInstantly {
            await apply(result)
        } else {
            // Too long to highlight: an empty diff tells the preview to show the plain result.
            let diff = edges.core.count > WordDiff.maxHighlightLength ? [] : WordDiff.spans(from: edges.core, to: fixed)
            state = .review(original: capture.text, result: result, diff: diff, usedBackup: model != primary)
        }
    }

    public func accept() async {
        guard case .review(_, let result, _, _) = state else { return }
        await apply(result)
    }

    private func apply(_ result: String) async {
        await willPaste?()
        do {
            try await text.paste(result, into: capture.focus)
            history.add(original: capture.text, result: result, commandName: command.name)
            state = .done
        } catch {
            state = .pasteRefused(result: result)
            pasteWasRefused?()
        }
    }

    public func copyResult(_ result: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
        history.add(original: capture.text, result: result, commandName: command.name)
    }

    public func cancel() { task?.cancel(); state = .done }
    public func retry() { task?.cancel(); task = Task { await run(quietRetry: false) } }  // manual retry: main once, then backup
}

extension AIError {
    enum Next { case stop, backup, retry }

    /// What the session does after this error on the main model.
    var next: Next {
        switch self {
        case .noKey, .unauthorized, .outOfCredit: .stop               // account problems fail on every model
        case .badRequest, .blocked, .timedOut: .backup               // the same model would fail again, or take another 60 s
        case .rateLimited, .server, .network, .emptyAnswer, .incomplete, .badResponse: .retry
        }
    }
}
