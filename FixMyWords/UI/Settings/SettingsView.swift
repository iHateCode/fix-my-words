import SwiftUI
import KeyboardShortcuts
import FixMyWordsCore

struct SettingsView: View {
    let coordinator: AppCoordinator

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettingsView(coordinator: coordinator) }
            Tab("AI", systemImage: "sparkles") { AISettingsView(keychain: coordinator.keychain) }
            Tab("Commands", systemImage: "list.bullet") { CommandsSettingsView(coordinator: coordinator) }
        }
        .frame(width: 620, height: 480)
    }
}

/// Every recorder refuses a shortcut already used by the main hotkey or by another command.
@MainActor
func hotkeyClashCheck(for name: KeyboardShortcuts.Name, commands: [Command])
    -> (KeyboardShortcuts.Shortcut) -> KeyboardShortcuts.ValidationResult {
    { shortcut in
        if name != .openCommandList, KeyboardShortcuts.getShortcut(for: .openCommandList) == shortcut {
            return .disallow(reason: "This shortcut already opens the command list.")
        }
        if let other = commands.first(where: {
            KeyboardShortcuts.Name.command($0.id) != name && KeyboardShortcuts.getShortcut(for: .command($0.id)) == shortcut
        }) {
            return .disallow(reason: "This shortcut is already used by “\(other.name)”.")
        }
        return .allow
    }
}
