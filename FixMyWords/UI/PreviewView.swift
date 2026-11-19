import SwiftUI
import FixMyWordsCore

struct PreviewActions {
    let accept: () -> Void
    let copy: (String) -> Void
    let dismiss: () -> Void                    // Cancel, Discard, Esc
    let retry: () -> Void
    let perform: (FixFailure.Action) -> Void
    let close: () -> Void
}

/// Renders `FixSession.state`.
struct PreviewView: View {
    let session: FixSession
    let actions: PreviewActions
    static let highlightLimit = WordDiff.maxHighlightLength   // longer selections skip the highlighted view

    private static let padding: CGFloat = 14
    private static let columnGap: CGFloat = 14
    private static let narrowWidth: CGFloat = 440
    private static let reviewWidth: CGFloat = 840
    private static let columnWidth = (reviewWidth - 2 * padding - columnGap) / 2
    /// About the largest the panel gets, used to pick its side and left edge once. Height, from the layout: two
    /// paddings (28), header (24), caption (13), text box (320), backup note (14), buttons (28), three 10-point
    /// gaps and one 4-point gap, about 461 for a review; paste-refused is about 464. These are estimates, not
    /// measured, and not a strict bound: long error text or a long command list can be taller. The clamp into
    /// the visible frame is the safety net.
    static let maxPanelSize = NSSize(width: reviewWidth, height: 480)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: session.command.name, close: actions.dismiss)
            content
        }
        .padding(Self.padding)
        .frame(width: width, alignment: .leading)
        .onChange(of: session.state, initial: true) { _, state in
            switch state {
            case .done: actions.close()
            case .noChanges:
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    if session.state == .noChanges { actions.dismiss() }
                }
            default: break
            }
        }
    }

    /// Streaming and the other states are one column; the review shows two equal columns side by side.
    private var width: CGFloat {
        if case .review(let original, _, _, _) = session.state, original.count <= Self.highlightLimit { return Self.reviewWidth }
        return Self.narrowWidth
    }

    @ViewBuilder private var content: some View {
        switch session.state {
        case .streaming(let partial):
            TextBox(Text(partial))
            HStack {
                ProgressView().controlSize(.small)
                Spacer()
                Button("Cancel", action: actions.dismiss).accessibilityIdentifier("preview.cancel")
            }

        case .review(let original, let result, let diff, let usedBackup):
            if original.count > Self.highlightLimit {
                TextBox(Text(result)).accessibilityIdentifier("preview.result")
                Text("Too long to highlight changes").font(.caption).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: Self.columnGap) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Changes").font(.caption).foregroundStyle(.secondary)
                        TextBox(Text(Self.attributed(diff)))
                            .accessibilityIdentifier("preview.diff")
                            .accessibilityLabel("Changes")
                            .accessibilityValue(Self.describe(diff))
                    }
                    .frame(width: Self.columnWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("New version").font(.caption).foregroundStyle(.secondary)
                        TextBox(Text(result))
                            .accessibilityIdentifier("preview.clean")
                            .accessibilityLabel("New version")
                    }
                    .frame(width: Self.columnWidth, alignment: .leading)
                }
            }
            if usedBackup {
                Text("Written by the backup model because the main model failed.")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("preview.backupNote")
            }
            HStack {
                Spacer()
                Button("Discard", action: actions.dismiss).accessibilityIdentifier("preview.discard")
                Button("Copy") { actions.copy(result) }.accessibilityIdentifier("preview.copy")
                Button("Replace", action: actions.accept)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("preview.replace")
            }

        case .noChanges:
            Message("No changes needed.")

        case .failed(let failure):
            FailureView(failure: failure) { action in
                action == .retry ? actions.retry() : actions.perform(action)
            }

        case .pasteRefused(let result):
            Message("Nothing was pasted, because your text box changed or couldn't be confirmed.")
            TextBox(Text(result)).accessibilityIdentifier("preview.result")
            HStack {
                Spacer()
                Button("Copy") { actions.copy(result) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("preview.copy")
            }

        case .done:
            EmptyView()
        }
    }

    /// Removed words struck through on red, added words on green; strikethrough keeps it readable without colour.
    static func attributed(_ spans: [DiffSpan]) -> AttributedString {
        spans.reduce(into: AttributedString()) { out, span in
            var piece = AttributedString(span.text)
            switch span.kind {
            case .same: break
            case .removed:
                piece.strikethroughStyle = .single
                piece.backgroundColor = Color(nsColor: .systemRed).opacity(0.25)
            case .added:
                piece.backgroundColor = Color(nsColor: .systemGreen).opacity(0.25)
            }
            out += piece
        }
    }

    /// The diff as plain text for Accessibility and UI tests: `[-removed-]` and `{+added+}`.
    static func describe(_ spans: [DiffSpan]) -> String {
        spans.map { span in
            switch span.kind {
            case .same: span.text
            case .removed: "[-\(span.text)-]"
            case .added: "{+\(span.text)+}"
            }
        }.joined()
    }
}

struct FailureView: View {
    let failure: FixFailure
    let perform: (FixFailure.Action) -> Void

    var body: some View {
        Message(failure.message)             // OpenRouter's reason is plain text only, never a link or Markdown
        if let action = failure.action {
            HStack {
                Spacer()
                Button(action.title) { perform(action) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("preview.action")
            }
        }
    }
}

extension FixFailure.Action {
    var title: String {
        switch self {
        case .openSettings: "Open Settings"
        case .openOpenRouter: "Open OpenRouter"
        case .openSystemSettings: "Open System Settings"
        case .retry: "Retry"
        }
    }
}

/// The panel's title with a close button on the right. The button does what Esc does, so nothing is pasted.
struct PanelHeader: View {
    let title: String
    let close: () -> Void
    var body: some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close (Esc)")
            .accessibilityLabel("Close")
            .accessibilityIdentifier("panel.close")
        }
    }
}

private struct Message: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(verbatim: text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("preview.message")
    }
}

private struct TextBox: View {
    let text: Text
    init(_ text: Text) { self.text = text }
    var body: some View {
        ScrollView {
            text.textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}
