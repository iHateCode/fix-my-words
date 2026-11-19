import AppKit
import KeyboardShortcuts
import FixMyWordsCore

@MainActor
final class AppCoordinator {
    let commands: CommandStore
    let history: HistoryStore
    let keychain = KeychainStore(service: AppSettings.shared.keychainService)
    let text: any TextAccess = SystemTextAccess()
    /// Pause unregisters every hotkey, so ⌘⇧W goes back to the frontmost app.
    var isPaused = false { didSet { KeyboardShortcuts.isEnabled = !isPaused } }
    private var session: FixSession?
    private var isCapturing = false
    private var ai: OpenRouterClient?                       // one client (and one URLSession) until Settings change
    private let panels = PanelController()
    private lazy var windows = WindowPresenter(coordinator: self)

    init(supportDirectory: URL) {
        commands = CommandStore(directory: supportDirectory)
        history = HistoryStore(directory: supportDirectory)
        panels.openSettings = { [weak self] in self?.showSettings() }
        registerCommandHotkeys()
    }

    func registerCommandHotkeys() {
        KeyboardShortcuts.removeAllHandlers()               // handlers stack if registered twice
        KeyboardShortcuts.onKeyUp(for: .openCommandList) { [weak self] in Task { await self?.trigger(command: nil) } }
        for command in commands.commands {
            KeyboardShortcuts.onKeyUp(for: .command(command.id)) { [weak self] in
                Task { await self?.trigger(command: command) }
            }
        }
    }

    /// Every change to the command list goes through here, so hotkeys always match the saved list.
    func saveCommands(_ updated: [Command]) throws {
        let removed = Set(commands.commands.map(\.id)).subtracting(updated.map(\.id))
        try commands.save(updated)
        for id in removed { KeyboardShortcuts.reset(.command(id)) }
        registerCommandHotkeys()
    }

    /// `command == nil` means "show the list first".
    func trigger(command: Command?) async {
        // One capture or paste at a time: two would save and restore the clipboard over each other.
        guard !isPaused, !isCapturing, !text.isUsingClipboard else { return }
        isCapturing = true
        session?.cancel()
        session = nil
        if panels.closeForCapture() { try? await Task.sleep(for: .milliseconds(50)) }   // let the target app's box take keys again
        let capture: Capture
        do { capture = try await text.capture(); isCapturing = false }
        catch { isCapturing = false; panels.showCaptureError(error, near: nil); return }

        let chosen: Command
        if let command { chosen = command }
        else {
            guard let picked = await panels.pickCommand(from: commands.commands, near: capture.selectionBounds) else { return }
            chosen = picked
        }

        let settings = AppSettings.shared.openRouterSettings
        if ai?.settings != settings {
            ai?.invalidate()
            ai = OpenRouterClient(settings: settings, keyProvider: { [keychain] in keychain.read() })
        }
        guard let ai else { return }
        let session = FixSession(capture: capture, command: chosen, ai: ai,
                                 primary: settings.primary, backup: settings.backup, text: text, history: history)
        self.session?.cancel()                              // one that started while the command list was open
        self.session = session
        panels.showPreview(for: session, near: capture.selectionBounds)
        session.start()
    }

    func showSettings() { windows.showSettings() }
    func showHistory() { windows.showHistory() }
}
