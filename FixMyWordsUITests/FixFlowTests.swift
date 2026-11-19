import AppKit
import XCTest

/// End-to-end tests. They drive the built Fix My Words against TestPad and the stub
/// OpenRouter server. They need Accessibility permission for the test runner and for Fix My Words,
/// granted once by hand in System Settings → Privacy & Security → Accessibility.
@MainActor
final class FixFlowTests: XCTestCase {
    nonisolated static let luna = "openai/gpt-6-luna"
    nonisolated static let gemini = "google/gemini-3.8-flash"
    nonisolated static let keychainService = "com.ihatecode.FixMyWords.uitest"
    nonisolated static let proofread = "Fix spelling, grammar and punctuation only. Do not change wording, tone or meaning."

    var stub: StubOpenRouter!
    var app: XCUIApplication!
    var pad: XCUIApplication!
    private var supportDirectory: URL!

    // MARK: 1–5: the basic flow

    func test01_reviewAndAccept() throws {
        try start(script: Self.fixTheir)
        try select("Their going")
        pressHotkey()
        pick("1")
        let diff = element("preview.diff")
        XCTAssertTrue(diff.waitForExistence(timeout: 10))
        XCTAssertTrue((diff.value as? String ?? "").contains("{+They're+}"), "They're should be marked as added")
        sendKey(Key.return)
        waitFor { self.padText() == "They're going" }
        // The paste's ⌘V must not leave ⌘ held system-wide, or the user's next click or key becomes a ⌘ shortcut.
        XCTAssertFalse(CGEventSource.flagsState(.combinedSessionState).contains(.maskCommand), "⌘ is still held after the paste")
    }

    func test02_discard() throws {
        try start(script: Self.fixTheir)
        try select("Their going")
        pressHotkey()
        pick("1")
        XCTAssertTrue(element("preview.diff").waitForExistence(timeout: 10))
        sendKey(Key.escape)
        waitFor { !self.element("preview.diff").exists }
        XCTAssertEqual(padText(), "Their going")
        XCTAssertTrue(historyFileEntries().isEmpty, "a discarded result must not be saved")
    }

    func test03_pickByNumber() throws {
        try start(script: Self.fixTheir)
        try select("Their going")
        pressHotkey()
        pick("1")
        waitFor { self.stub.requests.count == 1 }
        XCTAssertEqual(stub.requests.first?.instruction, Self.proofread)
    }

    func test04_applyInstantly() throws {
        try start(script: Self.fixTheir, instantProofread: true)
        try select("Their going")
        pressHotkey()
        pick("1")
        waitFor { self.padText() == "They're going" }
        XCTAssertFalse(app.buttons["preview.replace"].exists, "an instant command skips the review")
    }

    func test05_pasteGuard() throws {
        // The answer must arrive after the click that moves focus.
        try start(script: { _, _ in .stream(["They're", " go", "ing"], delay: .seconds(3)) }, instantProofread: true)
        try select("Their going")
        pressHotkey()
        pick("1")
        pad.textViews["pad2.text"].click()                  // move focus while the fix is still running
        XCTAssertTrue(message(containing: "Nothing was pasted").waitForExistence(timeout: 10))
        XCTAssertEqual(padText(), "Their going")
    }

    // MARK: 6–8: retries, backup and missing key

    func test06_quietRetryBackupThenError() throws {
        try start(script: { _, _ in .status(500) })
        try select("Their going")
        pressHotkey()
        pick("1")
        XCTAssertTrue(message(containing: "OpenRouter didn't answer.").waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["preview.action"].label, "Retry")
        XCTAssertEqual(padText(), "Their going")
        XCTAssertEqual(stub.requests.map(\.model), [Self.luna, Self.luna, Self.gemini])
        XCTAssertEqual(stub.requests.map(\.effort), ["none", "none", "low"])
    }

    func test07_retrySucceedsAfterOneFailure() throws {
        try start(script: { request, index in index == 0 ? .status(500) : Self.fixTheir(request, index) })
        try select("Their going")
        pressHotkey()
        pick("1")
        XCTAssertTrue(element("preview.diff").waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["preview.message"].exists)
        XCTAssertEqual(stub.requests.map(\.model), [Self.luna, Self.luna])
    }

    func test08_noKey() throws {
        // A Keychain service nothing ever writes to stands in for "the item was deleted", so the test never
        // deletes a real Keychain item.
        try start(script: Self.fixTheir, keychainService: Self.keychainService + ".nokey", saveKey: false)
        try select("Their going")
        pressHotkey()
        pick("1")
        XCTAssertTrue(message(containing: "No OpenRouter key yet.").waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["preview.action"].label, "Open Settings")
        XCTAssertTrue(stub.requests.isEmpty)
    }

    // MARK: 9–12: clipboard, history, commands

    func test09_clipboardKept() throws {
        try start(script: Self.fixTheir)
        try select("Their going")
        setClipboard("KEEP-ME")
        pressHotkey()
        pick("1")
        XCTAssertTrue(element("preview.diff").waitForExistence(timeout: 10))
        sendKey(Key.return)
        waitFor { self.padText() == "They're going" }
        waitFor { NSPasteboard.general.string(forType: .string) == "KEEP-ME" }
    }

    func test10_history() throws {
        try start(script: Self.fixTheir)
        try select("Their going")
        pressHotkey()
        pick("1")
        XCTAssertTrue(element("preview.diff").waitForExistence(timeout: 10))
        sendKey(Key.return)
        waitFor { self.padText() == "They're going" }

        openMenuItem("History…")
        let entries = app.descendants(matching: .any).matching(identifier: "history.entry")
        waitFor { entries.count == 1 }
        XCTAssertEqual(entries.firstMatch.staticTexts["history.original"].value as? String ?? entries.firstMatch.staticTexts["history.original"].label, "Their going")
        XCTAssertEqual(entries.firstMatch.staticTexts["history.result"].value as? String ?? entries.firstMatch.staticTexts["history.result"].label, "They're going")
    }

    func test11_customCommand() throws {
        try start(script: Self.fixTheir)
        openMenuItem("Settings…")
        let settings = app.windows["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tabs["Commands"].firstMatch.click()
        settings.buttons["commands.add"].click()
        let name = settings.textFields["commands.name"]
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Pirate")
        settings.textViews["commands.instruction"].click()
        settings.textViews["commands.instruction"].typeText("Talk like a pirate.")
        settings.buttons[XCUIIdentifierCloseWindow].click()

        try select("Their going")
        pressHotkey()
        XCTAssertTrue(app.buttons["commandList.row.Pirate"].waitForExistence(timeout: 10))
        pick("6")                                            // the sixth command, after the five built-ins
        waitFor { self.stub.requests.count == 1 }
        XCTAssertEqual(stub.requests.first?.instruction, "Talk like a pirate.")
    }

    func test12_importRejectsBadFile() throws {
        try start(script: Self.fixTheir)
        let before = try Data(contentsOf: supportDirectory.appending(path: "commands.json"))
        let bad = supportDirectory.appending(path: "bad-commands.json")
        try Data(#"{"version": 99, "commands": []}"#.utf8).write(to: bad)

        openMenuItem("Settings…")
        let settings = app.windows["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tabs["Commands"].firstMatch.click()
        settings.buttons["Import…"].click()
        let chooseFile = app.dialogs.buttons["Choose File…"]                 // the "replaces your commands" warning
        XCTAssertTrue(chooseFile.waitForExistence(timeout: 5))
        chooseFile.click()
        let openPanel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(openPanel.waitForExistence(timeout: 5))
        openPanel.typeKey("g", modifierFlags: [.command, .shift])      // "Go to folder"
        openPanel.typeText(bad.path + "\n")
        openPanel.buttons["OKButton"].click()                          // Return is not reliably taken as "Open"
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@",
                                                             "version 99", "version 99")).firstMatch
            .waitForExistence(timeout: 5))
        XCTAssertEqual(try Data(contentsOf: supportDirectory.appending(path: "commands.json")), before)
    }

    // MARK: 13–17: broken streams, timeouts, backup, refusals, edges

    func test13_streamBreaksPartway() throws {
        try start(script: { _, _ in .stream(["They're", " go", "ing"], finish: .error(code: 502, message: "Upstream error")) },
                  instantProofread: true)
        try select("Their going")
        pressHotkey()
        pick("1")
        XCTAssertTrue(message(containing: "OpenRouter didn't answer.").waitForExistence(timeout: 15))
        XCTAssertEqual(padText(), "Their going")
        XCTAssertEqual(stub.requests.count, 3)
    }

    func test14_wholeRequestTimeout() throws {
        try start(script: { _, _ in .keepAliveForever() }, extraEnvironment: ["FMW_OPENROUTER_TIMEOUT": "3"])
        try select("Their going")
        pressHotkey()
        pick("1")
        XCTAssertTrue(message(containing: "OpenRouter took longer than 60 seconds.").waitForExistence(timeout: 12))
        XCTAssertEqual(app.buttons["preview.action"].label, "Retry")
        XCTAssertEqual(stub.requests.map(\.model), [Self.luna, Self.gemini])
    }

    func test15_backupWritesTheFix() throws {
        try start(script: { request, index in request.model == Self.luna ? .status(500) : Self.fixTheir(request, index) })
        try select("Their going")
        pressHotkey()
        pick("1")
        XCTAssertTrue(element("preview.backupNote").waitForExistence(timeout: 15))
        XCTAssertEqual(stub.requests.count, 3)
        XCTAssertEqual(stub.requests.last?.effort, "low")
    }

    func test16_refusedRequest() throws {
        try start(script: { _, _ in .status(400, message: "No such model") })
        try select("Their going")
        pressHotkey()
        pick("1")
        XCTAssertTrue(message(containing: "OpenRouter refused this request: No such model").waitForExistence(timeout: 10))
        XCTAssertEqual(stub.requests.count, 2, "a refusal skips the quiet retry")
    }

    func test17_trailingLineBreakKept() throws {
        // "No changes needed" closes itself after 1.5 s, so the answer comes quickly for the test to catch it.
        try start(script: { _, _ in .stream(["All good here."], delay: .milliseconds(500)) })
        try select("All good here.\n")
        pressHotkey()
        pick("1")
        XCTAssertTrue(message(containing: "No changes needed.").waitForExistence(timeout: 10))
        XCTAssertEqual(padText(), "All good here.\n")
    }

    // MARK: 20: AI settings

    func test20_aiSettingsKeyAndModels() throws {
        let deep = "test/deep-thinker"
        try start(script: Self.fixTheir, models: [
            ["id": Self.luna, "name": "GPT-6 Luna", "reasoning": ["supported_efforts": ["high", "low", "none"]]],
            ["id": Self.gemini, "name": "Gemini 3.8 Flash", "reasoning": ["supported_efforts": ["high", "low", "none"]]],
            // Thinking can't be switched off for this one, so "Off" must not be offered.
            ["id": deep, "name": "Deep Thinker", "reasoning": ["supported_efforts": ["high", "low", "none"], "mandatory": true]],
        ])

        openMenuItem("Settings…")
        let settings = app.windows["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tabs["AI"].firstMatch.click()
        settings.buttons["settings.testKey"].click()
        XCTAssertTrue(settings.staticTexts["Key works"].waitForExistence(timeout: 10))

        let model = settings.popUpButtons["settings.primary.model"]
        XCTAssertTrue(model.waitForExistence(timeout: 10), "the model list didn't load")
        model.click()
        app.menuItems["Deep Thinker"].click()
        let effort = settings.popUpButtons["settings.primary.effort"]
        effort.click()
        XCTAssertTrue(app.menuItems["High"].waitForExistence(timeout: 5))            // the menu is open
        XCTAssertFalse(app.menuItems["Off"].exists, "a model that must think is never offered Off")
        app.menuItems["High"].click()
        settings.buttons[XCUIIdentifierCloseWindow].click()

        try select("Their going")
        pressHotkey()
        pick("1")
        waitFor { self.stub.requests.count == 1 }
        XCTAssertEqual(stub.requests.first?.model, deep)
        XCTAssertEqual(stub.requests.first?.effort, "high")
    }

    // MARK: 21: the close button

    func test21_closeButton() throws {
        try start(script: Self.fixTheir)
        try select("Their going")
        pressHotkey()
        XCTAssertTrue(app.textFields["commandList.search"].waitForExistence(timeout: 10))
        app.buttons["panel.close"].click()
        waitFor { !self.app.textFields["commandList.search"].exists }

        try select("Their going")                           // XCUITest's click brought Fix My Words to the front; a real click doesn't
        pressHotkey()
        pick("1")
        XCTAssertTrue(element("preview.diff").waitForExistence(timeout: 10))
        app.buttons["panel.close"].click()
        waitFor { !self.element("preview.diff").exists }
        XCTAssertEqual(padText(), "Their going")
        XCTAssertTrue(historyFileEntries().isEmpty, "a closed result must not be saved")
    }

    // MARK: 18–19: pause and the ⌘C path

    func test18_pauseGivesShortcutBack() throws {
        try start(script: Self.fixTheir)
        openMenuItem("Pause")
        try select("Their going")
        pressHotkey()
        XCTAssertTrue(pad.staticTexts["hotkeyLabel"].waitForExistence(timeout: 5))
        waitFor { (self.pad.staticTexts["hotkeyLabel"].value as? String) == "got ⌘⇧W" }
        XCTAssertFalse(app.textFields["commandList.search"].exists)
    }

    func test19_clipboardKeptOnCopyPath() throws {
        try start(script: Self.fixTheir)
        try select("Their going", in: "copyOnly")
        setClipboard("KEEP-ME")
        pressHotkey()
        pick("1")
        XCTAssertTrue(element("preview.diff").waitForExistence(timeout: 10))
        XCTAssertEqual(stub.requests.first?.text, "Their going")
        sendKey(Key.return)
        waitFor { self.padText(in: "copyOnly") == "They're going" }
        waitFor { NSPasteboard.general.string(forType: .string) == "KEEP-ME" }
    }

    // MARK: 22–24: the preview panel's size and layout

    func test22_panelStaysOnScreenAtTheBottom() throws {
        try checkPanelWhileStreaming(padBottomGap: 0, textDistance: 0...100, checkNoJump: false)
    }

    func test24_panelDoesNotJumpWithTextInTheMiddleBand() throws {
        // The Pad's window sits 220 pt up, which puts its first line about 280 pt above the visible bottom.
        try checkPanelWhileStreaming(padBottomGap: 220, textDistance: 200...400, checkNoJump: true)
    }

    func test23_reviewShowsTheCleanVersion() throws {
        try start(script: Self.fixTheir)
        try select("Their going")
        pressHotkey()
        pick("1")
        let diff = element("preview.diff")
        let clean = element("preview.clean")
        XCTAssertTrue(diff.waitForExistence(timeout: 10))
        XCTAssertTrue(clean.waitForExistence(timeout: 5), "the plain new version should sit beside the changes")

        // Read the text the box shows, not a value the app writes for the test.
        let shownText = clean.staticTexts.firstMatch
        XCTAssertTrue(shownText.exists, "no static text inside preview.clean: \(clean.debugDescription)")
        let value = shownText.value as? String ?? ""
        let shown = value.isEmpty ? shownText.label : value
        XCTAssertEqual(shown, "They're going", clean.debugDescription)
        XCTAssertFalse(shown.contains("[-") || shown.contains("{+"), "the clean version must have no markers")
        XCTAssertGreaterThanOrEqual(clean.frame.minX, diff.frame.maxX - 1, "the clean version belongs to the right of the changes")

        let panel = try XCTUnwrap(panelFrame(), "panel was never found")
        XCTAssertEqual(panel.width, 840, accuracy: 40)
    }

    // MARK: Helpers (several are internal, not private, so DemoTests.swift can use them)

    /// Streams a long answer next to a Pad whose text sits `padBottomGap` pt above the bottom, and samples the
    /// panel all the way through: inside the visible area, never over the text, always on the same side of it,
    /// and (when asked) with the edge nearest the text not moving.
    private func checkPanelWhileStreaming(padBottomGap: Int, textDistance: ClosedRange<CGFloat>, checkNoJump: Bool) throws {
        // Enough text to fill the 320-point box, arriving a chunk at a time so the panel grows while it is visible.
        let sentence = "This answer is long on purpose, so the box keeps growing as it streams in. "
        let chunks = ["They're going. "] + (1...30).map { _ in sentence }
        try start(script: { _, _ in .stream(chunks, chunkDelay: .milliseconds(200)) }, padBottomGap: padBottomGap)

        let padWindow = pad.windows["Pad"]
        XCTAssertTrue(padWindow.waitForExistence(timeout: 5))
        let visible = visibleArea(containing: padWindow.frame)

        try select("Their going")
        // The text view is taller than its scroll view shows and is scrolled to the end, so only the part inside
        // the scroll view is text the user can see.
        let scroll = padWindow.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists, "no scroll view in the Pad window")
        let text = pad.textViews["pad1.text"].frame.intersection(scroll.frame)
        XCTAssertFalse(text.isNull, "the Pad's text view and scroll view don't meet")
        // The selected text must sit where the test says, or it proves nothing.
        let distance = visible.maxY - text.maxY
        XCTAssertTrue(textDistance.contains(distance), "the text is \(distance) pt above the visible bottom, not within \(textDistance)")
        pressHotkey()
        pick("1")

        var tallest: CGFloat = 0
        var seen = 0
        var sides = Set<String>()
        var lastAnchor: CGFloat?
        func sample() {
            guard let (panel, listShowing, ids) = panelSnapshot() else { return }
            seen += 1
            tallest = max(tallest, panel.height)
            XCTAssertTrue(visible.insetBy(dx: -1, dy: -1).contains(panel), "panel \(panel) is outside the visible area \(visible)")
            let overlap = panel.intersection(text)
            XCTAssertTrue(overlap.isNull || overlap.width < 4 || overlap.height < 4, "panel \(panel) covers the visible text \(text); union of \(ids)")
            let above = panel.midY < text.midY
            sides.insert(above ? "above" : "below")
            // The edge nearest the text is the one that must hold still once the list has handed over to the preview.
            guard checkNoJump, !listShowing else { return }
            let anchor = above ? panel.maxY : panel.minY
            if let lastAnchor { XCTAssertLessThanOrEqual(abs(anchor - lastAnchor), 2, "panel jumped from \(lastAnchor) to \(anchor)") }
            lastAnchor = anchor
        }
        let deadline = Date.now.addingTimeInterval(40)
        while !element("preview.diff").exists && Date.now < deadline {
            sample()
            RunLoop.current.run(until: .now.addingTimeInterval(0.1))
        }
        XCTAssertTrue(element("preview.diff").exists, "the review never appeared")
        for _ in 0..<10 {                                    // the panel widens and settles after the review shows
            sample()
            RunLoop.current.run(until: .now.addingTimeInterval(0.1))
        }
        XCTAssertGreaterThan(seen, 0, "panel was never found: none of its elements exist")
        XCTAssertEqual(sides.count, 1, "the panel changed sides of the text: \(sides)")
        XCTAssertGreaterThanOrEqual(tallest, 320, "the answer was too short to fill the box, so the test proves nothing")
    }

    /// The panel's frame without a window lookup (the floating panel isn't reachable as an XCUITest window):
    /// the union of its own elements, outset by the panel's 14-point padding, from one query so the elements
    /// can't change between a check and a read. Nil if none exist. `listShowing` is whether the command list's
    /// search field was in the same snapshot.
    private func panelSnapshot() -> (frame: CGRect, listShowing: Bool, ids: [String])? {
        let ids = ["panel.close", "preview.diff", "preview.clean", "preview.result", "preview.message", "preview.replace",
                   "preview.discard", "preview.copy", "preview.cancel", "preview.action", "preview.backupNote"]
        let found = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier IN %@", ids + ["commandList.search"])).allElementsBoundByIndex
        let listShowing = found.contains { $0.identifier == "commandList.search" }
        let panelElements = found.filter { $0.identifier != "commandList.search" }
        let frames = panelElements.map(\.frame)
        guard let first = frames.first else { return nil }
        // While streaming the union is only panel.close and preview.cancel: its top and bottom are the panel's,
        // but its width is not the panel's width until the review appears.
        return (frames.dropFirst().reduce(first) { $0.union($1) }.insetBy(dx: -14, dy: -14), listShowing,
                panelElements.map(\.identifier))
    }

    func panelFrame() -> CGRect? { panelSnapshot()?.frame }

    /// "Their going" → "They're going", in three chunks.
    nonisolated static func fixTheir(_ request: StubOpenRouter.Request, _ index: Int) -> StubOpenRouter.Response {
        .stream(["They're", " go", "ing"])
    }

    func start(script: @escaping @Sendable (StubOpenRouter.Request, Int) -> StubOpenRouter.Response,
               instantProofread: Bool = false,
               keychainService: String = FixFlowTests.keychainService,
               saveKey: Bool = true,
               models: [[String: Any]]? = nil,
               padBottomGap: Int? = nil,
               padArguments: [String] = [],
               extraEnvironment: [String: String] = [:]) throws {
        continueAfterFailure = false
        stub = try StubOpenRouter()
        stub.script = script
        stub.models = models
        try stub.start()

        supportDirectory = FileManager.default.temporaryDirectory.appending(path: "fmw-uitest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try writeCommands(instantProofread: instantProofread)

        pad = XCUIApplication(bundleIdentifier: "com.ihatecode.FixMyWords.TestPad")
        if let padBottomGap { pad.launchArguments = ["-padBottomGap", "\(padBottomGap)"] }   // TestPad's test-only seam
        pad.launchArguments += padArguments
        pad.launch()

        app = XCUIApplication()
        app.launchEnvironment = [
            "FMW_OPENROUTER_BASE_URL": stub.baseURL,
            "FMW_KEYCHAIN_SERVICE": keychainService,
            "FMW_SUPPORT_DIRECTORY": supportDirectory.path,
            // Settings changes stay out of the real ones. The launch arguments below reset the model keys each run.
            "FMW_DEFAULTS_SUITE": "com.ihatecode.FixMyWords.uitest",
        ].merging(extraEnvironment) { $1 }
        // Launch arguments override UserDefaults for this run only, so the real settings are untouched.
        app.launchArguments = ["-primaryModel", Self.luna, "-primaryEffort", "none",
                               "-backupModel", Self.gemini, "-backupEffort", "low",
                               "-historyEnabled", "YES"]
        app.launch()

        addTeardownBlock { @MainActor [app, pad, stub, supportDirectory] in
            app?.terminate()
            pad?.terminate()
            stub?.stop()
            if let supportDirectory { try? FileManager.default.removeItem(at: supportDirectory) }
        }

        if saveKey { saveTestKey() }
    }

    /// The five built-ins, written to the scratch support folder so every test starts from the same list.
    private func writeCommands(instantProofread: Bool) throws {
        let builtIns: [(String, String, String)] = [
            ("proofread", "Proofread", Self.proofread),
            ("rewrite", "Rewrite", "Rewrite this to read more clearly. Keep the meaning and roughly the same length."),
            ("friendlier", "Friendlier", "Make this warmer and friendlier. Keep the meaning."),
            ("professional", "More professional", "Make this more professional and polished. Keep the meaning."),
            ("shorter", "Shorter", "Make this shorter. Keep every important point."),
        ]
        let commands = builtIns.map { id, name, instruction in
            ["id": UUID().uuidString, "name": name, "instruction": instruction,
             "applyInstantly": instantProofread && id == "proofread", "builtInID": id] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: ["version": 1, "commands": commands], options: [.sortedKeys])
        try data.write(to: supportDirectory.appending(path: "commands.json"))
    }

    /// Stores a dummy key under the test Keychain service through Settings, the way a user would.
    private func saveTestKey() {
        openMenuItem("Settings…")
        let settings = app.windows["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tabs["AI"].firstMatch.click()
        let field = settings.secureTextFields["settings.key"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.click()
        field.typeText(StubOpenRouter.validKey)
        settings.buttons["settings.saveKey"].click()
        settings.buttons[XCUIIdentifierCloseWindow].click()
    }

    func openMenuItem(_ title: String) {
        let item = app.statusItems.firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.click()
        app.menuItems[title].click()
    }

    /// Replaces a TestPad window's text with `text`, then selects all of it.
    private func select(_ text: String, in pane: String = "pad1") throws {
        pad.activate()
        let view = pad.textViews["\(pane).text"]
        XCTAssertTrue(view.waitForExistence(timeout: 5))
        view.click()
        view.typeKey("a", modifierFlags: .command)
        view.typeKey(.delete, modifierFlags: [])
        view.typeText(text)
        view.typeKey("a", modifierFlags: .command)
    }

    /// The visible area (screen minus menu bar and Dock) of the screen holding `rect`, in the top-left screen
    /// coordinates XCUIElement frames use. AppKit's `visibleFrame` has its origin bottom-left, and the primary
    /// screen's height is what flips the two.
    private func visibleArea(containing rect: CGRect) -> CGRect {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let areas = NSScreen.screens.map { screen -> (frame: CGRect, visible: CGRect) in
            func flipped(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height) }
            return (flipped(screen.frame), flipped(screen.visibleFrame))
        }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        return (areas.first { $0.frame.contains(centre) } ?? areas[0]).visible
    }

    func padText(in pane: String = "pad1") -> String? { pad.textViews["\(pane).text"].value as? String }

    /// The hotkey fires on key-up; TestPad stays frontmost, as in real use.
    func pressHotkey() { sendKey(Key.w, flags: [.maskCommand, .maskShift]) }

    /// Keys go to the key window, which is Fix My Words' non-activating panel while TestPad stays active.
    func pick(_ number: String) {
        XCTAssertTrue(app.textFields["commandList.search"].waitForExistence(timeout: 10), "command list didn't appear")
        sendKey(Key.digits[number]!)
    }

    enum Key {
        static let w: CGKeyCode = 13, `return`: CGKeyCode = 36, escape: CGKeyCode = 53
        static let digits: [String: CGKeyCode] = ["1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
                                                   "6": 22, "7": 26, "8": 28, "9": 25]
    }

    /// Posts a key press straight to the system, as a person's keyboard would. For keys Fix My Words takes
    /// (its hotkey, and keys for its panel): `typeKey` waits for the addressed app to receive them, and when
    /// it never does, XCUITest stalls 10 s on every press.
    func sendKey(_ code: CGKeyCode, flags: CGEventFlags = []) {
        // Modifiers go down and up as flagsChanged events, the way a hand does. A plain key-up for ⌘ is ignored,
        // which leaves ⌘ held system-wide and turns the next menu bar click into a ⌘-drag.
        let modifiers: [(CGEventFlags, CGKeyCode)] = [(.maskCommand, 55), (.maskShift, 56)].filter { flags.contains($0.0) }
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ key: CGKeyCode, down: Bool, flags: CGEventFlags, modifier: Bool = false) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
            if modifier { event.type = .flagsChanged }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
        var held: CGEventFlags = []
        for (flag, key) in modifiers { held.insert(flag); post(key, down: true, flags: held, modifier: true) }
        post(code, down: true, flags: held)
        post(code, down: false, flags: held)
        for (flag, key) in modifiers.reversed() { held.remove(flag); post(key, down: false, flags: held, modifier: true) }
        RunLoop.current.run(until: .now.addingTimeInterval(0.3))
    }

    func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func message(containing text: String) -> XCUIElement {
        app.staticTexts.matching(identifier: "preview.message")
            .containing(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", text, text)).firstMatch
    }

    private func setClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func historyFileEntries() -> [Any] {
        let url = supportDirectory.appending(path: "history.json")
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [Any] ?? []
    }

    func waitFor(timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line,
                 _ condition: @escaping () -> Bool) {
        let deadline = Date.now.addingTimeInterval(timeout)
        while !condition() {
            guard Date.now < deadline else { return XCTFail("condition not met within \(timeout) s", file: file, line: line) }
            RunLoop.current.run(until: .now.addingTimeInterval(0.1))
        }
    }
}
