import SwiftUI
import FixMyWordsCore

@main
struct FixMyWordsApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        // Settings and History are AppKit windows owned by the coordinator, not SwiftUI scenes: a menu-bar-only
        // app has to bring itself forward before opening them, which the coordinator does in one place.
        MenuBarExtra("Fix My Words", image: "MenuBarIcon") {
            MenuBarMenu(coordinator: delegate.coordinator)
        }
    }
}
