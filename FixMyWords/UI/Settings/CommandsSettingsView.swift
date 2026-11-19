import AppKit
import SwiftUI
import KeyboardShortcuts
import UniformTypeIdentifiers
import FixMyWordsCore

struct CommandsSettingsView: View {
    let coordinator: AppCoordinator
    @State private var selection: Command.ID?
    @State private var errorMessage: String?

    private var commands: [Command] { coordinator.commands.commands }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(commands) { command in
                        Text(command.name.isEmpty ? "Untitled" : command.name).tag(command.id)
                    }
                    .onMove { from, to in
                        var updated = commands
                        updated.move(fromOffsets: from, toOffset: to)
                        save(updated)
                    }
                }
                .accessibilityIdentifier("commands.list")
                HStack {
                    Button { add() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Add command")
                        .accessibilityIdentifier("commands.add")
                    Button { deleteSelected() } label: { Image(systemName: "minus") }
                        .accessibilityLabel("Delete command")
                        .disabled(selection == nil)
                    Spacer()
                    Button("Import…") { importCommands() }
                    Button("Export…") { exportCommands() }
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(minWidth: 200, maxWidth: 240)

            Group {
                if let index = commands.firstIndex(where: { $0.id == selection }) {
                    CommandEditor(command: binding(for: index), commands: commands) {
                        do { try coordinator.commands.resetToDefault(commands[index]); coordinator.registerCommandHotkeys() }
                        catch { errorMessage = "Couldn't save your commands." }
                    }
                    .id(commands[index].id)
                } else {
                    Text("Select a command").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 340)
        }
        .alert("Commands", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(verbatim: errorMessage ?? "")
        }
    }

    /// Edits save straight away, so hotkeys and the command list always match what's on screen.
    private func binding(for index: Int) -> Binding<Command> {
        Binding(get: { commands[index] }, set: { edited in
            var updated = commands
            updated[index] = edited
            save(updated)
        })
    }

    private func save(_ updated: [Command]) {
        do { try coordinator.saveCommands(updated) }
        catch { errorMessage = "Couldn't save your commands." }
    }

    private func add() {
        let command = Command(name: "New command", instruction: "")
        save(commands + [command])
        selection = command.id
    }

    private func deleteSelected() {
        guard let selection else { return }
        save(commands.filter { $0.id != selection })
        self.selection = nil
    }

    private func importCommands() {
        // Import replaces the whole list, so say so first and offer a backup.
        let count = coordinator.commands.commands.count
        let warning = NSAlert()
        warning.messageText = "Importing replaces your \(count) command\(count == 1 ? "" : "s")."
        warning.informativeText = "Commands that aren't in the file will be removed, along with their hotkeys."
        warning.addButton(withTitle: "Choose File…")
        warning.addButton(withTitle: "Export First…")
        warning.addButton(withTitle: "Cancel")
        switch warning.runModal() {
        case .alertFirstButtonReturn: break
        case .alertSecondButtonReturn: guard exportCommands() else { return }
        default: return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.message = "Importing replaces all your current commands."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try coordinator.commands.importFile(url)
            coordinator.registerCommandHotkeys()
            selection = nil
        } catch let error as CommandImportError {
            errorMessage = switch error {
            case .unsupportedVersion(let version): "This file is from a different version of Fix My Words (version \(version)), so nothing was imported."
            case .empty: "This file has no commands, so nothing was imported."
            case .invalidCommand(let name): "The command “\(name.isEmpty ? "Untitled" : name)” has an instruction over 4,000 characters, so nothing was imported."
            }
        } catch {
            errorMessage = "This isn't a Fix My Words commands file, so nothing was imported."
        }
    }

    /// Returns true when the file was written.
    @discardableResult
    private func exportCommands() -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Fix My Words commands.json"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do { try coordinator.commands.exportFile(to: url); return true }
        catch { errorMessage = "Couldn't write the file."; return false }
    }
}

private struct CommandEditor: View {
    @Binding var command: Command
    let commands: [Command]
    let resetToDefault: () -> Void
    static let instructionLimit = 4_000

    var body: some View {
        Form {
            TextField("Name", text: $command.name)
                .accessibilityIdentifier("commands.name")
            VStack(alignment: .leading) {
                Text("Instruction")
                TextEditor(text: Binding(get: { command.instruction },
                                         set: { command.instruction = String($0.prefix(Self.instructionLimit)) }))
                    .font(.body)
                    .frame(minHeight: 120)
                    .accessibilityIdentifier("commands.instruction")
                Text("\(command.instruction.count) / 4,000").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Apply instantly (skip the preview)", isOn: $command.applyInstantly)
            KeyboardShortcuts.Recorder("Hotkey:", name: .command(command.id))
                .shortcutValidation(hotkeyClashCheck(for: .command(command.id), commands: commands))
            if command.builtInID != nil {
                Button("Reset to default", action: resetToDefault)
            }
        }
        .formStyle(.grouped)
    }
}
