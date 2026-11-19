import Foundation

public struct Command: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var instruction: String      // plain English, e.g. "Fix spelling and grammar only."
    public var applyInstantly: Bool     // skip the preview
    public var builtInID: String?       // "proofread", "rewrite", … ; nil for user commands

    public init(id: UUID = UUID(), name: String, instruction: String,
                applyInstantly: Bool = false, builtInID: String? = nil) {
        self.id = id; self.name = name; self.instruction = instruction
        self.applyInstantly = applyInstantly; self.builtInID = builtInID
    }
}

public struct CommandFile: Codable, Sendable {
    public static let currentVersion = 1
    public var version: Int
    public var commands: [Command]
}
