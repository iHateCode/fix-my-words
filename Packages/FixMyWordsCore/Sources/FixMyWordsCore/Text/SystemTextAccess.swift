import AppKit

/// Reads the selection through Accessibility, or a guarded ⌘C in Chromium apps and when the read fails,
/// and writes back by pasting (see docs/adr/0002-capture-per-engine-paste-write.md).
@MainActor
public final class SystemTextAccess: TextAccess {
    // Provisional: not yet measured whether Teams behaves like Edge, or whether Word and Outlook need adding.
    static let chromiumBundleIDs: Set<String> = ["com.google.Chrome", "com.microsoft.edgemac", "com.microsoft.teams2"]
    static let chromiumFrameworks = ["Electron Framework.framework", "Chromium Embedded Framework.framework"]
    private var chromiumCache: [String: Bool] = [:]
    public private(set) var isUsingClipboard = false

    public init() {}

    // MARK: Capture

    public func capture() async throws -> Capture {
        // 1. Checked on every capture, so a revoked permission never fails silently.
        guard AXIsProcessTrusted() else { throw CaptureError.noPermission }
        guard let app = NSWorkspace.shared.frontmostApplication else { throw CaptureError.nothingSelected }

        // 2. The focus snapshot, always from the target app's own element, never the system-wide one.
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var element = Self.element(appElement, kAXFocusedUIElementAttribute)
        if element == nil {
            // Provisional: not yet measured whether the light nudge plus 150 ms is enough after a fresh launch.
            _ = Self.copyAttribute(appElement, kAXRoleAttribute)      // light nudge; never AXEnhancedUserInterface
            try await Task.sleep(for: .milliseconds(150))
            element = Self.element(appElement, kAXFocusedUIElementAttribute)
        }
        let focus = Self.snapshot(pid: app.processIdentifier, appElement: appElement, element: element)

        // 3–4. Chromium apps skip the Accessibility read: it isn't trusted for the selected text.
        if !isChromium(app), let element, let read = Self.readSelection(element) {
            guard !read.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CaptureError.nothingSelected
            }
            return Capture(text: read.text, focus: focus,
                           selectionBounds: read.range.flatMap { Self.bounds(element, $0) }, method: .accessibility)
        }

        // 5–6. The guarded clipboard copy. Chromium apps never report bounds, so the panel goes by the pointer.
        let copied = try await copyViaClipboard()
        guard !copied.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CaptureError.nothingSelected }
        return Capture(text: copied, focus: focus, selectionBounds: nil, method: .clipboard)
    }

    func isChromium(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        if Self.chromiumBundleIDs.contains(id) { return true }
        if let known = chromiumCache[id] { return known }
        let frameworks = app.bundleURL?.appendingPathComponent("Contents/Frameworks", isDirectory: true)
        let found = frameworks.map { dir in
            Self.chromiumFrameworks.contains { FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path) }
        } ?? false
        chromiumCache[id] = found
        return found
    }

    // Provisional: not yet proven in real use that this stops the stray "c" and puts the clipboard back exactly.
    func copyViaClipboard() async throws -> String {
        // 1. Wait for the user to let go of ⌘, ⇧, ⌥ and ⌃ (up to 1 s). This is the fix for "typed c over my text".
        let deadline = ContinuousClock.now + .seconds(1)
        while !NSEvent.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty {
            guard ContinuousClock.now < deadline else { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        isUsingClipboard = true
        defer { isUsingClipboard = false }
        let pasteboard = NSPasteboard.general
        let saved = ClipboardSnapshot(pasteboard)            // every item, every type
        let before = pasteboard.changeCount

        // 2. Post ⌘C with only the command flag set, so held physical keys can't leak into it.
        Self.postCommandKey(0x08)                            // 0x08 = "c"

        // 3. Wait for the clipboard to change (up to 1 s).
        let copyDeadline = ContinuousClock.now + .seconds(1)
        while pasteboard.changeCount == before {
            guard ContinuousClock.now < copyDeadline else { saved.restore(to: pasteboard); throw CaptureError.copyTimedOut }
            try await Task.sleep(for: .milliseconds(10))
        }
        let text = pasteboard.string(forType: .string) ?? ""

        // 4. Put the user's clipboard back.
        saved.restore(to: pasteboard)
        return text
    }

    // MARK: Paste

    public func paste(_ text: String, into target: FocusSnapshot) async throws {
        try await activate(target.pid)
        // Provisional: not yet measured whether focused-element handles are stable enough for this guard.
        guard let now = currentFocus(), now.isSameTarget(as: target) else { throw PasteError.targetChanged }

        isUsingClipboard = true
        defer { isUsingClipboard = false }
        let pasteboard = NSPasteboard.general
        let saved = ClipboardSnapshot(pasteboard)
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)                  // plain text only
        // nspasteboard.org markers: clipboard managers skip transient, app-generated content.
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))
        pasteboard.writeObjects([item])
        let ours = pasteboard.changeCount

        Self.postCommandKey(0x09)                               // 0x09 = "v"

        // Give the target app time to read the clipboard, then restore it — but only if nobody else wrote to it since.
        // Provisional: not yet measured whether 400 ms is long enough in Word, Outlook and Teams.
        // `try?`: a cancel during the wait must not skip putting the user's clipboard back.
        try? await Task.sleep(for: .milliseconds(400))
        if pasteboard.changeCount == ours { saved.restore(to: pasteboard) }
    }

    public func currentFocus() -> FocusSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        return Self.snapshot(pid: app.processIdentifier, appElement: appElement,
                             element: Self.element(appElement, kAXFocusedUIElementAttribute))
    }

    /// Brings the target app back to the front and waits up to 1 s for it.
    private func activate(_ pid: pid_t) async throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != pid,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate()
        let deadline = ContinuousClock.now + .seconds(1)
        while NSWorkspace.shared.frontmostApplication?.processIdentifier != pid, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: Accessibility helpers

    private static func snapshot(pid: pid_t, appElement: AXUIElement, element: AXUIElement?) -> FocusSnapshot {
        let window = Self.element(appElement, kAXFocusedWindowAttribute)
        let title = window.flatMap { copyAttribute($0, kAXTitleAttribute) as? String }
        return FocusSnapshot(pid: pid, windowNumber: frontWindowNumber(pid: pid), windowTitle: title, element: element)
    }

    /// The first normal-layer window of `pid` in the on-screen list, which runs front to back.
    /// The list's titles need Screen Recording permission, so the title comes from Accessibility instead.
    private static func frontWindowNumber(pid: pid_t) -> Int? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        return list.first {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }?[kCGWindowNumber as String] as? Int
    }

    /// `AXSelectedText`, else `AXValue` cut by `AXSelectedTextRange`. Nil when neither gives text.
    // Provisional: not yet measured whether Word and Outlook allow this read.
    private static func readSelection(_ element: AXUIElement) -> (text: String, range: CFRange?)? {
        let range = selectedRange(element)
        if let selected = copyAttribute(element, kAXSelectedTextAttribute) as? String, !selected.isEmpty {
            return (selected, range)
        }
        guard let range, range.length > 0, range.location >= 0,
              let value = copyAttribute(element, kAXValueAttribute) as? String else { return nil }
        let whole = value as NSString
        guard range.location + range.length <= whole.length else { return nil }
        let cut = whole.substring(with: NSRange(location: range.location, length: range.length))
        return cut.isEmpty ? nil : (cut, range)
    }

    private static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let value = copyAttribute(element, kAXSelectedTextRangeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var range = CFRange()
        return AXValueGetValue(value as! AXValue, .cfRange, &range) ? range : nil
    }

    /// Screen rectangle of the selection, in Accessibility coordinates (origin top-left of the main screen).
    // Provisional: not yet measured whether Safari, Outlook and Word give a usable rectangle.
    private static func bounds(_ element: AXUIElement, _ range: CFRange) -> CGRect? {
        var range = range
        guard let rangeValue = AXValueCreate(.cfRange, &range) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, rangeValue, &out) == .success,
              let out, CFGetTypeID(out) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(out as! AXValue, .cgRect, &rect), rect.width > 0 || rect.height > 0 else { return nil }
        return rect
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copyAttribute(parent, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    /// Posts ⌘+key with only the command flag set, from a private event source.
    /// Presses and releases ⌘ around the key. Setting only the ⌘ flag on the key events leaves ⌘ held
    /// system-wide afterwards, so the user's next click or key press would act as a ⌘ shortcut.
    private static func postCommandKey(_ key: CGKeyCode) {
        let source = CGEventSource(stateID: .privateState)
        let command: CGKeyCode = 0x37
        func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags, modifier: Bool = false) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
            if modifier { event.type = .flagsChanged }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        post(command, down: true, flags: .maskCommand, modifier: true)
        post(key, down: true, flags: .maskCommand)
        post(key, down: false, flags: .maskCommand)
        post(command, down: false, flags: [], modifier: true)
    }
}

public enum PasteError: Error, Equatable { case targetChanged }
