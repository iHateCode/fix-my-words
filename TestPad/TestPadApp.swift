import AppKit

/// The "other app" the UI tests write in. Three windows:
/// - "Pad": a plain NSTextView, plus a label that the ⌘⇧W menu item sets (test 18).
/// - "Second pad": somewhere to move focus for the paste guard test (test 5).
/// - "Copy-only pad": a text view that hides its selection from Accessibility, so Fix My Words
///   has to fall back to the guarded ⌘C (test 19).
@main
@MainActor
final class TestPadApp: NSObject, NSApplicationDelegate {
    private static let shared = TestPadApp()                   // NSApplication.delegate is weak
    private var windows: [NSWindow] = []
    private let hotkeyLabel = NSTextField(labelWithString: "")

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.delegate = shared
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = makeMenu()
        hotkeyLabel.setAccessibilityIdentifier("hotkeyLabel")
        // Test-only: `-padBottomGap <points>` lifts "Pad" that far above the bottom of the visible screen and
        // shrinks it; `-padAtBottom YES` is the same with a gap of 0.
        let defaults = UserDefaults.standard
        let gap: CGFloat? = defaults.object(forKey: "padBottomGap") != nil ? CGFloat(defaults.double(forKey: "padBottomGap"))
            : defaults.bool(forKey: "padAtBottom") ? 0 : nil
        // Demo-only: `-demoFrame "x,y,w,h"` (top-left screen points) shows just "Pad", that big and in larger type,
        // so the README screenshots and video show one clean window. `-demoText` (percent-encoded) fills it.
        if let demoFrame = defaults.string(forKey: "demoFrame") {
            windows = [makeDemoWindow(frame: demoFrame, text: defaults.string(forKey: "demoText")?.removingPercentEncoding ?? "")]
        } else {
            windows = [
                makeWindow(title: "Copy-only pad", id: "copyOnly", textView: CopyOnlyTextView(), at: NSPoint(x: 200, y: 160)),
                makeWindow(title: "Second pad", id: "pad2", textView: NSTextView(), at: NSPoint(x: 700, y: 420)),
                makeWindow(title: "Pad", id: "pad1", textView: NSTextView(), at: NSPoint(x: 200, y: 420), extra: hotkeyLabel,
                           bottomGap: gap),
            ]
        }
        windows.forEach { $0.makeKeyAndOrderFront(nil) }       // "Pad" ends up in front
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @objc private func gotShortcut(_ sender: Any?) { hotkeyLabel.stringValue = "got ⌘⇧W" }

    private func makeMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu()
        appItem.submenu?.addItem(withTitle: "Quit TestPad", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        // ⌘⇧W: only reaches TestPad while Fix My Words is paused (test 18).
        let testItem = NSMenuItem()
        let test = NSMenu(title: "Test")
        let shortcut = NSMenuItem(title: "Shortcut Check", action: #selector(gotShortcut(_:)), keyEquivalent: "w")
        shortcut.keyEquivalentModifierMask = [.command, .shift]
        shortcut.target = self
        test.addItem(shortcut)
        testItem.submenu = test
        main.addItem(testItem)
        return main
    }

    /// "Pad" alone at a fixed frame, given as "x,y,w,h" in top-left screen points like `screencapture -R`.
    private func makeDemoWindow(frame: String, text: String) -> NSWindow {
        let parts = frame.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        let rect = parts.count == 4 ? NSRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
            : NSRect(x: 200, y: 200, width: 1280, height: 600)
        let textView = NSTextView()
        let window = makeWindow(title: "Pad", id: "pad1", textView: textView, at: .zero)
        textView.font = .systemFont(ofSize: 20)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.string = text
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        window.setFrame(NSRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height), display: true)
        return window
    }

    private func makeWindow(title: String, id: String, textView: NSTextView, at origin: NSPoint,
                            extra: NSView? = nil, bottomGap: CGFloat? = nil) -> NSWindow {
        // At the bottom the window is short, so the selected text sits within 80 points of the screen edge.
        let height: CGFloat = bottomGap != nil ? 96 : 220
        let textHeight: CGFloat = bottomGap != nil ? 30 : 170
        let window = NSWindow(contentRect: NSRect(origin: origin, size: NSSize(width: 420, height: height)),
                              styleMask: [.titled, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false

        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.font = .systemFont(ofSize: 14)
        textView.frame = NSRect(x: 0, y: 0, width: 400, height: textHeight)
        textView.minSize = NSSize(width: 0, height: textHeight)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.setAccessibilityIdentifier("\(id).text")

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = textView
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [scroll] + (extra.map { [$0] } ?? []))
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        scroll.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16).isActive = true
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: textHeight).isActive = true
        window.contentView = stack
        window.initialFirstResponder = textView
        if let bottomGap, let screen = NSScreen.main ?? NSScreen.screens.first {
            window.setFrameOrigin(NSPoint(x: origin.x, y: screen.visibleFrame.minY + bottomGap))
        }
        return window
    }
}

/// Reports no selection to Accessibility, so an Accessibility read finds nothing and the capture uses ⌘C.
final class CopyOnlyTextView: NSTextView {
    override func accessibilitySelectedText() -> String? { nil }
    override func accessibilitySelectedTextRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
}
