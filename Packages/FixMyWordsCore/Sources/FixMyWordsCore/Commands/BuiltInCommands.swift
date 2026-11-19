import Foundation

public enum BuiltInCommands {
    // Fixed ids, so a built-in's hotkey ("command-<uuid>") survives a relaunch before the list is first saved.
    public static let all: [Command] = [
        Command(id: UUID(uuidString: "5F1C0001-0000-4000-8000-000000000001")!, name: "Proofread",
                instruction: "Fix spelling, grammar and punctuation only. Do not change wording, tone or meaning.",
                builtInID: "proofread"),
        Command(id: UUID(uuidString: "5F1C0001-0000-4000-8000-000000000002")!, name: "Rewrite",
                instruction: "Rewrite this to read more clearly. Keep the meaning and roughly the same length.",
                builtInID: "rewrite"),
        Command(id: UUID(uuidString: "5F1C0001-0000-4000-8000-000000000003")!, name: "Friendlier",
                instruction: "Make this warmer and friendlier. Keep the meaning.",
                builtInID: "friendlier"),
        Command(id: UUID(uuidString: "5F1C0001-0000-4000-8000-000000000004")!, name: "More professional",
                instruction: "Make this more professional and polished. Keep the meaning.",
                builtInID: "professional"),
        Command(id: UUID(uuidString: "5F1C0001-0000-4000-8000-000000000005")!, name: "Shorter",
                instruction: "Make this shorter. Keep every important point.",
                builtInID: "shorter"),
    ]

    public static func defaultCommand(for builtInID: String) -> Command? {
        all.first { $0.builtInID == builtInID }
    }
}
