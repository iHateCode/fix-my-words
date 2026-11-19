import Foundation
import Observation

@MainActor @Observable
public final class CommandStore {
    public private(set) var commands: [Command] = []
    private let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appending(path: "commands.json")
        do {
            commands = try Self.read(fileURL)
        } catch {
            commands = BuiltInCommands.all      // a broken file was already set aside by the app delegate
        }
    }

    public func save(_ updated: [Command]) throws {
        let data = try JSONEncoder.pretty.encode(CommandFile(version: CommandFile.currentVersion, commands: updated))
        try data.write(to: fileURL, options: [.atomic])   // atomic: a crash never leaves half a file
        commands = updated
    }

    public func resetToDefault(_ command: Command) throws {
        guard let builtIn = command.builtInID, var fresh = BuiltInCommands.defaultCommand(for: builtIn) else { return }
        fresh.id = command.id                          // keep the id so its hotkey survives
        try save(commands.map { $0.id == command.id ? fresh : $0 })
    }

    public func importFile(_ url: URL) throws {
        let file = try JSONDecoder().decode(CommandFile.self, from: Data(contentsOf: url))
        guard file.version == CommandFile.currentVersion else { throw CommandImportError.unsupportedVersion(file.version) }
        guard !file.commands.isEmpty else { throw CommandImportError.empty }
        // An empty name is allowed, as in the editor, which shows it as "Untitled"; so every export imports again.
        for c in file.commands where c.instruction.count > 4_000 {
            throw CommandImportError.invalidCommand(c.name)
        }
        try save(file.commands)                        // replace, not merge
    }

    public func exportFile(to url: URL) throws {
        try JSONEncoder.pretty.encode(CommandFile(version: CommandFile.currentVersion, commands: commands))
            .write(to: url, options: [.atomic])
    }

    private static func read(_ url: URL) throws -> [Command] {
        try JSONDecoder().decode(CommandFile.self, from: Data(contentsOf: url)).commands
    }
}

public enum CommandImportError: Error, Equatable {
    case unsupportedVersion(Int), empty, invalidCommand(String)
}

extension JSONEncoder {
    static let pretty: JSONEncoder = { let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e }()
}
