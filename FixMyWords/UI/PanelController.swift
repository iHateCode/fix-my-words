import AppKit
import SwiftUI
import FixMyWordsCore

/// Shows the one floating panel: the command list, then the preview in the same panel, or a capture error.
@MainActor
final class PanelController {
    var openSettings: () -> Void = {}
    private let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 160))
    private var pendingPick: CheckedContinuation<Command?, Never>?
    private var autoClose: Task<Void, Never>?
    private var placement: PanelPlacement?
    /// True while our own code changes the frame, so a move notification can be told from the user dragging.
    private var settingFrame = false
    /// The user dragged the panel: leave it where they put it until the next fresh `present()`.
    private var userMoved = false
    /// The window size at the last resize; a move with this same size is not AppKit growing the window.
    private var lastSize = NSSize.zero

    /// What a fresh placement reserves when choosing the side and the left edge (see `PanelPlacement`).
    private enum Reserve {
        case list           // the preview's height, so both pick the same side, but only the list's own width
        case preview        // the preview at its largest
        case fitting        // just the content as it first appears
    }

    init() {
        lastSize = panel.frame.size
        // Streaming growth, the review widening and error text all resize the window; re-place it each time.
        // Both observers have no queue, so they run synchronously and `settingFrame` is still set when our own
        // setFrame resizes or moves the panel.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: panel, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.lastSize = self?.panel.frame.size ?? .zero
                self?.keepOnScreen()
            }
        }
        // A drag is a move with the left mouse button held and the size unchanged: when AppKit grows the window
        // from a fixed top-left corner the origin moves too, but the size just changed.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.settingFrame, self.panel.frame.size == self.lastSize,
                      NSEvent.pressedMouseButtons & 1 != 0 else { return }
                self.userMoved = true
            }
        }
    }

    private func setFrame(_ frame: NSRect) {
        settingFrame = true
        defer { settingFrame = false }
        panel.setFrame(frame, display: true)
    }

    /// Only the origin can change here, so this sends no further resize notification and cannot loop.
    private func keepOnScreen() {
        guard panel.isVisible, !settingFrame, let placement else { return }
        // After a drag, don't go back to the selection; only shift the panel back inside its screen.
        let frame = userMoved ? PanelPlacement.fitted(panel.frame) : placement.frame(for: panel.frame.size)
        if frame != panel.frame { setFrame(frame) }
    }

    // MARK: Command list

    func pickCommand(from commands: [Command], near bounds: CGRect?) async -> Command? {
        finishPick(nil)
        let model = CommandListModel(commands: commands)
        return await withCheckedContinuation { continuation in
            pendingPick = continuation
            panel.keyHandler = { [weak self] event in
                guard let self, let action = model.action(for: event) else { return false }
                switch action {
                case .pick(let command): finishPick(command)
                case .close: finishPick(nil); close()
                case .handled: break
                }
                return true
            }
            present(CommandListView(model: model,
                                    onPick: { [weak self] command in self?.finishPick(command) },
                                    onClose: { [weak self] in self?.finishPick(nil); self?.close() }),
                    near: bounds, reusePosition: false, reserving: .list)
        }
    }

    private func finishPick(_ command: Command?) {
        pendingPick?.resume(returning: command)
        pendingPick = nil
    }

    // MARK: Preview

    func showPreview(for session: FixSession, near bounds: CGRect?) {
        finishPick(nil)
        let pid = session.capture.focus.pid
        session.willPaste = { [weak self] in await self?.handBack(to: pid) }
        session.pasteWasRefused = { [weak self] in self?.panel.makeKeyAndOrderFront(nil) }
        let actions = PreviewActions(
            accept: { Task { await session.accept() } },
            copy: { result in session.copyResult(result); session.cancel() },
            dismiss: { session.cancel() },
            retry: { session.retry() },
            perform: { [weak self] action in session.cancel(); self?.perform(action) },
            close: { [weak self] in self?.close() })

        panel.keyHandler = { event in
            switch (event.keyCode, session.state) {
            case (53, _):                                   // Esc: cancel, discard or close, whatever is showing
                actions.dismiss(); return true
            case (36, .review), (76, .review):              // Return / keypad Enter
                actions.accept(); return true
            case (8, .review(_, let result, _, _)) where event.modifierFlags.contains(.command),
                 (8, .pasteRefused(let result)) where event.modifierFlags.contains(.command):   // ⌘C
                actions.copy(result); return true
            default:
                return false
            }
        }
        // Reuse the list's position when the list was showing, so the panel doesn't jump.
        present(PreviewView(session: session, actions: actions), near: bounds, reusePosition: true, reserving: .preview)
    }

    /// Before any paste, reviewed or instant: hide the panel so it stops taking key presses, and give the
    /// target app focus back, so the ⌘V reaches the user's text box.
    private func handBack(to pid: pid_t) async {
        panel.orderOut(nil)
        if let app = NSRunningApplication(processIdentifier: pid), !app.isActive {
            app.activate(options: [])
            let deadline = ContinuousClock.now + .seconds(1)
            while NSWorkspace.shared.frontmostApplication?.processIdentifier != pid, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
    }

    /// Before a new capture: a visible panel holds the keyboard and would receive the capture's ⌘C.
    /// Returns true when the panel was showing.
    func closeForCapture() -> Bool {
        guard panel.isVisible else { return false }
        finishPick(nil)
        close()
        return true
    }

    // MARK: Capture errors

    func showCaptureError(_ error: Error, near bounds: CGRect?) {
        finishPick(nil)
        let failure = FixFailure(error)
        panel.keyHandler = { [weak self] event in
            guard event.keyCode == 53 else { return false }
            self?.close(); return true
        }
        let view = VStack(alignment: .leading, spacing: 10) {
            PanelHeader(title: "Fix My Words", close: { [weak self] in self?.close() })
            FailureView(failure: failure, perform: { [weak self] action in self?.close(); self?.perform(action) })
        }
        .padding(14)
        .frame(width: 440, alignment: .leading)
        present(view, near: bounds, reusePosition: false, reserving: .fitting)
        if let capture = error as? CaptureError, capture == .nothingSelected || capture == .copyTimedOut {
            closeAfter(.seconds(2))
        }
    }

    // MARK: Plumbing

    func closeAfter(_ delay: Duration) {
        autoClose = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }

    private func close() {
        autoClose?.cancel()
        panel.keyHandler = nil
        panel.orderOut(nil)
        panel.contentViewController = nil
    }

    private func perform(_ action: FixFailure.Action) {
        switch action {
        case .openSettings: openSettings()
        case .openOpenRouter: NSWorkspace.shared.open(Links.openRouterCredits)
        case .openSystemSettings: NSWorkspace.shared.open(Links.accessibilitySettings)
        case .retry: break          // handled by the session before we get here
        }
    }

    private func present<Content: View>(_ view: Content, near bounds: CGRect?, reusePosition: Bool, reserving: Reserve) {
        autoClose?.cancel()
        let keeping = reusePosition && panel.isVisible
        if !keeping { userMoved = false }
        let oldFrame = panel.frame
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        hosting.safeAreaRegions = []    // the hidden title bar is a 32-point safe-area inset that would grow the window past the frame we set
        settingFrame = true         // the swap resizes the panel; we place it right after
        panel.contentViewController = hosting
        settingFrame = false
        let size = hosting.view.fittingSize
        let next = (keeping ? placement : nil).map { PanelPlacement(continuing: $0, from: oldFrame) }
            ?? PanelPlacement(selectionBounds: bounds, reserving: {
                switch reserving {
                case .list: NSSize(width: 0, height: PreviewView.maxPanelSize.height)
                case .preview: PreviewView.maxPanelSize
                case .fitting: size
                }
            }())
        placement = next
        setFrame(next.frame(for: size, current: userMoved ? oldFrame : nil))
        panel.makeKeyAndOrderFront(nil)
    }
}
