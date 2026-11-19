import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI
import FixMyWordsCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Created in `init`, not in `applicationDidFinishLaunching`, because SwiftUI can build the menu bar scene first.
    let coordinator: AppCoordinator
    private var brokenCommandsFile = BrokenCommandsFile.none
    private var permissionWindow: NSWindow?
    private var permissionTimer: Timer?

    override init() {
        let directory = Self.supportDirectory()
        brokenCommandsFile = Self.setAsideBrokenCommandsFile(in: directory)
        coordinator = AppCoordinator(supportDirectory: directory)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if brokenCommandsFile != .none {
            NSApp.activate()
            let alert = NSAlert()
            alert.messageText = brokenCommandsFile == .setAside
                ? "Your saved commands couldn't be read. A copy was kept."
                : "Your saved commands couldn't be read, and Fix My Words couldn't keep a copy. "
                  + "The file will be replaced the next time you change a command. It is in ~/Library/Application Support/FixMyWords/commands.json."
            alert.runModal()
        }
        if !AXIsProcessTrusted() { showPermissionWindow() }
        registerLoginItemOnFirstLaunch()
    }

    /// `~/Library/Application Support/FixMyWords/`, owner only.
    private static func supportDirectory() -> URL {
        #if DEBUG
        // UI tests point the app at a scratch folder so they never touch the real commands or history.
        if let override = ProcessInfo.processInfo.environment["FMW_SUPPORT_DIRECTORY"], !override.isEmpty {
            return ensureOwnerOnly(URL(filePath: override, directoryHint: .isDirectory))
        }
        #endif
        return ensureOwnerOnly(URL.applicationSupportDirectory.appending(path: "FixMyWords", directoryHint: .isDirectory))
    }

    private static func ensureOwnerOnly(_ url: URL) -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } else {
            try? fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        }
        return url
    }

    /// If `commands.json` exists but can't be decoded, rename it so the store starts from the built-ins
    /// and the user's file survives.
    private enum BrokenCommandsFile { case none, setAside, couldNotSetAside }

    private static func setAsideBrokenCommandsFile(in directory: URL) -> BrokenCommandsFile {
        let file = directory.appending(path: "commands.json")
        guard let data = try? Data(contentsOf: file) else { return .none }
        if (try? JSONDecoder().decode(CommandFile.self, from: data)) != nil { return .none }
        let stamp = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: ":", with: "-")
        do { try FileManager.default.moveItem(at: file, to: directory.appending(path: "commands.broken-\(stamp).json")) }
        catch { return .couldNotSetAside }
        return .setAside
    }

    private func registerLoginItemOnFirstLaunch() {
        #if DEBUG
        return   // a Debug build in DerivedData must not become a login item; only an installed Release build registers
        #else
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: "didRegisterLoginItem") else { return }
        try? SMAppService.mainApp.register()
        defaults.set(true, forKey: "didRegisterLoginItem")
        #endif
    }

    // MARK: First-run permission window

    private func showPermissionWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 220),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Fix My Words"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: PermissionView())
        window.center()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        permissionWindow = window
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard AXIsProcessTrusted() else { return }
                self?.permissionTimer?.invalidate()
                self?.permissionWindow?.close()
            }
        }
    }
}

private struct PermissionView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Fix My Words needs Accessibility permission").font(.headline)
            Text("It uses Accessibility to read the text you select, to check that you are still in the same text box, and to paste the fixed text back. Nothing is read until you press the shortcut.")
                .fixedSize(horizontal: false, vertical: true)
            Text("Turn on Fix My Words in System Settings → Privacy & Security → Accessibility. This window closes by itself once it's on.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open System Settings") {
                // The prompt option also adds Fix My Words to the Accessibility list, so the user only flips a switch.
                _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
                NSWorkspace.shared.open(Links.accessibilitySettings)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .frame(width: 440)
    }
}

enum Links {
    static let accessibilitySettings = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    static let openRouterCredits = URL(string: "https://openrouter.ai/settings/credits")!
}
