import AppKit
import XCTest

/// Demo runs for the README's screenshots and video. They skip unless the runner has `FMW_DEMO=1`
/// (pass `TEST_RUNNER_FMW_DEMO=1` to xcodebuild), so the normal suite is unchanged. They use the stub
/// OpenRouter only. `scripts/record-demo.sh` runs them and records the screen around TestPad's "Pad".
extension FixFlowTests {
    nonisolated static let demoEmail = """
        Hi Sam,

        Thanks for sending the report yesterday. I has a few questions about the budget section and I definately \
        want to go over them before we send it. Their expecting the final version on friday, so could we meet \
        tomorrow morning?

        Best,
        Alex
        """

    nonisolated static let demoProofread = """
        Hi Sam,

        Thanks for sending the report yesterday. I have a few questions about the budget section and I definitely \
        want to go over them before we send it. They're expecting the final version on Friday, so could we meet \
        tomorrow morning?

        Best,
        Alex
        """

    nonisolated static let demoFriendlier = """
        Hi Sam,

        Thanks so much for sending the report yesterday! I have a few questions about the budget section, and I'd \
        love to go over them with you before we send it. They're expecting the final version on Friday, so could we \
        grab a coffee tomorrow morning?

        Best,
        Alex
        """

    /// Proofread, review, Replace; then Friendlier, review, Replace. Streams word by word so it can be seen.
    func testDemo_video() throws {
        try XCTSkipUnless(Self.demoEnabled, "set FMW_DEMO=1 to run the demo")
        try startDemo()

        mark("ready")                                  // the recording is trimmed to start here
        pause(1.5)
        selectAll()
        pause(1.0)
        pressHotkey()
        XCTAssertTrue(app.textFields["commandList.search"].waitForExistence(timeout: 10), "command list didn't appear")
        pause(1.5)
        sendKey(Key.digits["1"]!)                      // Proofread
        XCTAssertTrue(element("preview.clean").waitForExistence(timeout: 30), "the review never appeared")
        mark("review")                                 // the poster frame is taken just after this
        pause(3.5)
        sendKey(Key.return)
        waitFor { self.padText() == Self.demoProofread }
        pause(2.0)

        selectAll()
        pause(0.8)
        pressHotkey()
        XCTAssertTrue(app.textFields["commandList.search"].waitForExistence(timeout: 10), "command list didn't appear")
        pause(1.2)
        sendKey(Key.digits["3"]!)                      // Friendlier
        XCTAssertTrue(element("preview.clean").waitForExistence(timeout: 30), "the review never appeared")
        pause(3.0)
        sendKey(Key.return)
        waitFor { self.padText() == Self.demoFriendlier }
        pause(2.0)
        mark("done")
    }

    /// The four README stills: command list, Settings → AI, Settings → Commands (the review panel is the video poster).
    func testDemo_screenshots() throws {
        try XCTSkipUnless(Self.demoEnabled, "set FMW_DEMO=1 to run the demo")
        try startDemo()

        selectAll()
        pressHotkey()
        XCTAssertTrue(app.textFields["commandList.search"].waitForExistence(timeout: 10), "command list didn't appear")
        pause(0.8)
        attach("command-list", screenshotOfDemoArea())
        sendKey(Key.escape)
        waitFor { !self.app.textFields["commandList.search"].exists }

        openMenuItem("Settings…")
        let settings = app.windows["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tabs["AI"].firstMatch.click()
        XCTAssertTrue(settings.popUpButtons["settings.primary.model"].waitForExistence(timeout: 10), "the model list didn't load")
        pause(0.8)
        attach("settings-ai", settings.screenshot().image)
        settings.tabs["Commands"].firstMatch.click()
        let proofread = settings.descendants(matching: .any)["commands.list"].staticTexts["Proofread"].firstMatch
        if proofread.waitForExistence(timeout: 5) { proofread.click() }
        XCTAssertTrue(settings.descendants(matching: .any)["commands.instruction"].waitForExistence(timeout: 5))
        pause(0.8)
        attach("settings-commands", settings.screenshot().image)
    }

    // MARK: Demo helpers

    nonisolated static var demoEnabled: Bool { ProcessInfo.processInfo.environment["FMW_DEMO"] == "1" }

    /// Where "Pad" sits, as "x,y,w,h" in top-left screen points: `FMW_DEMO_FRAME`, or 1280×600 centred on the
    /// main screen. The recording script passes the same rectangle to `screencapture -R`.
    var demoFrame: CGRect {
        let parts = (ProcessInfo.processInfo.environment["FMW_DEMO_FRAME"] ?? "")
            .split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 4 { return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]) }
        let screen = NSScreen.screens.first?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let size = CGSize(width: 1280, height: 600)
        return CGRect(x: ((screen.width - size.width) / 2).rounded(), y: ((screen.height - size.height) / 2).rounded(),
                      width: size.width, height: size.height)
    }

    /// Launches against the stub with the demo email in a lone, large "Pad", and saves the dummy key
    /// before anything worth recording happens.
    func startDemo() throws {
        let frame = demoFrame
        try start(script: { request, _ in
            let answer = request.instruction?.hasPrefix("Make this warmer") == true ? Self.demoFriendlier : Self.demoProofread
            return .stream(Self.wordChunks(answer), delay: .milliseconds(400), chunkDelay: .milliseconds(90))
        }, models: [
            ["id": Self.luna, "name": "GPT-6 Luna", "reasoning": ["supported_efforts": ["high", "low", "none"]]],
            ["id": Self.gemini, "name": "Gemini 3.8 Flash", "reasoning": ["supported_efforts": ["high", "low", "none"]]],
        ], padArguments: ["-demoFrame", "\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))",
                          // Percent-encoded: a launch argument loses everything after its first line break.
                          "-demoText", Self.demoEmail.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""])
        pad.activate()
        XCTAssertTrue(pad.windows["Pad"].waitForExistence(timeout: 5))
        XCTAssertEqual(padText(), Self.demoEmail)
    }

    /// Splits text into word-sized chunks, each keeping the space or line break that follows it.
    nonisolated static func wordChunks(_ text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == " " || character == "\n" { chunks.append(current); current = "" }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    func selectAll() {
        pad.activate()
        let view = pad.textViews["pad1.text"]
        XCTAssertTrue(view.waitForExistence(timeout: 5))
        view.typeKey("a", modifierFlags: .command)
    }

    func pause(_ seconds: TimeInterval) { RunLoop.current.run(until: .now.addingTimeInterval(seconds)) }

    /// A wall-clock marker in the test log, used to trim the recording.
    func mark(_ label: String) { print("FMWDEMO \(label) \(String(format: "%.3f", Date().timeIntervalSince1970))") }

    /// The screen inside the demo rectangle: "Pad" and anything Fix My Words shows over it.
    func screenshotOfDemoArea() -> NSImage {
        let screen = XCUIScreen.main.screenshot().image
        let points = NSScreen.screens.first?.frame.size ?? screen.size
        guard let cg = screen.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return screen }
        let scale = CGFloat(cg.width) / points.width
        let frame = demoFrame
        let crop = CGRect(x: frame.minX * scale, y: frame.minY * scale, width: frame.width * scale, height: frame.height * scale)
        guard let cropped = cg.cropping(to: crop) else { return screen }
        return NSImage(cgImage: cropped, size: frame.size)
    }

    func attach(_ name: String, _ image: NSImage) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
