import Foundation
import Observation

public struct HistoryEntry: Codable, Identifiable, Sendable {
    public var id = UUID()
    public let date: Date
    public let commandName: String
    public let original: String
    public let result: String
}

@MainActor @Observable
public final class HistoryStore {
    public private(set) var entries: [HistoryEntry] = []
    public var isEnabled: Bool { didSet { UserDefaults.standard.set(isEnabled, forKey: "historyEnabled") } }
    private let fileURL: URL
    static let retention: TimeInterval = 30 * 24 * 60 * 60     // matches the "30 days" promise in General settings

    public init(directory: URL) {
        fileURL = directory.appending(path: "history.json")
        isEnabled = UserDefaults.standard.object(forKey: "historyEnabled") as? Bool ?? true
        entries = (try? JSONDecoder().decode([HistoryEntry].self, from: Data(contentsOf: fileURL))) ?? []
        prune()
    }

    public func add(original: String, result: String, commandName: String) {
        guard isEnabled else { return }
        entries.insert(HistoryEntry(date: .now, commandName: commandName, original: original, result: result), at: 0)
        prune()
        write()
    }

    public func clear() { entries = []; write() }

    public func search(_ query: String) -> [HistoryEntry] {
        guard !query.isEmpty else { return entries }
        return entries.filter { $0.original.localizedCaseInsensitiveContains(query) || $0.result.localizedCaseInsensitiveContains(query) }
    }

    private func prune() { entries.removeAll { $0.date < Date.now.addingTimeInterval(-Self.retention) } }

    private func write() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)  // owner only
    }
}
