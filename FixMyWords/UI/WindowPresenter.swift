import AppKit
import SwiftUI

/// Owns the Settings and History windows. A menu-bar-only app has to bring itself forward,
/// or its windows open behind the app the user is in.
@MainActor
final class WindowPresenter {
    private unowned let coordinator: AppCoordinator
    private var settingsWindow: NSWindow?
    private var historyWindow: NSWindow?

    init(coordinator: AppCoordinator) { self.coordinator = coordinator }

    func showSettings() {
        settingsWindow = show(settingsWindow, title: "Fix My Words Settings", identifier: "settings") {
            SettingsView(coordinator: coordinator)
        }
    }

    func showHistory() {
        historyWindow = show(historyWindow, title: "History", identifier: "history") {
            HistoryView(store: coordinator.history)
        }
    }

    private func show<Content: View>(_ existing: NSWindow?, title: String, identifier: String,
                                     content: () -> Content) -> NSWindow {
        let window = existing ?? {
            let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
            window.title = title
            window.identifier = NSUserInterfaceItemIdentifier(identifier)
            window.styleMask.insert(.resizable)
            window.isReleasedWhenClosed = false
            window.center()
            return window
        }()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        return window
    }
}
