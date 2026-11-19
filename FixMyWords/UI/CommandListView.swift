import AppKit
import SwiftUI
import FixMyWordsCore

@MainActor @Observable
final class CommandListModel {
    enum Action { case pick(Command), close, handled }

    let commands: [Command]
    var query = ""
    var selection = 0

    init(commands: [Command]) { self.commands = commands }

    /// Commands matching the search, each with its number in the stored list (1–9, none from 10 on).
    var visible: [(number: Int?, command: Command)] {
        commands.enumerated()
            .filter { query.isEmpty || $0.element.name.localizedCaseInsensitiveContains(query) }
            .map { (number: $0.offset < 9 ? $0.offset + 1 : nil, command: $0.element) }
    }

    /// Keys from the panel, before the search field sees them. Digits pick by stored number,
    /// so they can't be typed into the search: a command whose name holds a digit is found by its other letters.
    func action(for event: NSEvent) -> Action? {
        let rows = visible
        switch event.keyCode {
        case 53: return .close                                        // Esc
        case 36, 76:                                                  // Return, keypad Enter
            return rows.indices.contains(selection) ? .pick(rows[selection].command) : .handled
        case 125: selection = min(selection + 1, max(rows.count - 1, 0)); return .handled   // ↓
        case 126: selection = max(selection - 1, 0); return .handled                        // ↑
        default: break
        }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let chars = event.charactersIgnoringModifiers, let digit = Int(chars), (1...9).contains(digit),
              commands.indices.contains(digit - 1) else { return nil }
        return .pick(commands[digit - 1])
    }
}

struct CommandListView: View {
    @Bindable var model: CommandListModel
    let onPick: (Command) -> Void
    let onClose: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PanelHeader(title: "Fix My Words", close: onClose)
            TextField("Search commands", text: $model.query)
                .textFieldStyle(.roundedBorder)
                .focused($searchFocused)
                .accessibilityIdentifier("commandList.search")
                .onChange(of: model.query) { model.selection = 0 }
            ForEach(Array(model.visible.enumerated()), id: \.element.command.id) { index, row in
                Button { onPick(row.command) } label: {
                    HStack {
                        Text(row.number.map(String.init) ?? " ")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 16, alignment: .trailing)
                        Text(row.command.name)
                        Spacer()
                    }
                    .padding(.vertical, 3)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                    .background(index == model.selection ? Color.accentColor.opacity(0.25) : .clear,
                                in: RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("commandList.row.\(row.command.name)")
            }
            if model.visible.isEmpty {
                Text("No matching command").foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(width: 280)
        .onAppear { searchFocused = true }
    }
}
