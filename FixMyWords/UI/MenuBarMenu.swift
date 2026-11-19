import SwiftUI

struct MenuBarMenu: View {
    let coordinator: AppCoordinator
    /// The menu is the only place that changes Pause, so local state mirrors the coordinator.
    @State private var isPaused: Bool

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        _isPaused = State(initialValue: coordinator.isPaused)
    }

    var body: some View {
        Button("Settings…") { coordinator.showSettings() }
            .keyboardShortcut(",")
        Button("History…") { coordinator.showHistory() }
        Toggle("Pause", isOn: $isPaused)
            .onChange(of: isPaused) { _, paused in coordinator.isPaused = paused }
        Divider()
        Button("Quit Fix My Words") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
