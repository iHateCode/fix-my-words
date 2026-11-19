import ServiceManagement
import SwiftUI
import KeyboardShortcuts
import FixMyWordsCore

struct GeneralSettingsView: View {
    let coordinator: AppCoordinator
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?
    @State private var confirmClear = false

    var body: some View {
        @Bindable var history = coordinator.history
        Form {
            KeyboardShortcuts.Recorder("Open command list:", name: .openCommandList)
                .shortcutValidation(hotkeyClashCheck(for: .openCommandList,
                                                                         commands: coordinator.commands.commands))

            Toggle("Start at login", isOn: Binding(
                get: { loginStatus == .enabled || loginStatus == .requiresApproval },
                set: setLoginItem))
            if loginStatus == .requiresApproval {
                Text("Allow Fix My Words in System Settings → General → Login Items.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let loginError {
                Text(loginError).font(.caption).foregroundStyle(.red)
            }

            Toggle("Keep a history of fixes (30 days)", isOn: $history.isEnabled)
            Text("Clipboard managers may record text copied from apps that Fix My Words can't read directly. Clipboard items over 50 MB aren't restored after that copy.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Clear history…") { confirmClear = true }
                .confirmationDialog("Delete every saved fix?", isPresented: $confirmClear) {
                    Button("Clear history", role: .destructive) { coordinator.history.clear() }
                }
        }
        .formStyle(.grouped)
    }

    private func setLoginItem(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }
}
