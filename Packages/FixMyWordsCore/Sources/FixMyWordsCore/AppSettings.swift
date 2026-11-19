import Foundation
import Observation

/// The app's settings in `UserDefaults`. `HistoryStore` owns the `historyEnabled` key.
@MainActor @Observable
public final class AppSettings {
    public static let shared = AppSettings(defaults: testDefaults ?? .standard)

    /// UI tests only: a separate settings store, so a test that changes a model never touches the real one.
    private static var testDefaults: UserDefaults? {
        #if DEBUG
        if let suite = ProcessInfo.processInfo.environment["FMW_DEFAULTS_SUITE"], !suite.isEmpty {
            return UserDefaults(suiteName: suite)
        }
        #endif
        return nil
    }

    private enum Key {
        static let primaryModel = "primaryModel", primaryEffort = "primaryEffort"
        static let backupModel = "backupModel", backupEffort = "backupEffort"
    }
    /// Stored for "this model has no thinking setting" (effort nil), because `UserDefaults` can't hold nil.
    /// A missing key means "use the default".
    private static let noEffort = ""

    private let defaults: UserDefaults

    public var primaryModel: String { didSet { defaults.set(primaryModel, forKey: Key.primaryModel) } }
    public var primaryEffort: String? { didSet { defaults.set(primaryEffort ?? Self.noEffort, forKey: Key.primaryEffort) } }
    public var backupModel: String { didSet { defaults.set(backupModel, forKey: Key.backupModel) } }
    public var backupEffort: String? { didSet { defaults.set(backupEffort ?? Self.noEffort, forKey: Key.backupEffort) } }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let fallback = OpenRouterClient.Settings()
        primaryModel = defaults.string(forKey: Key.primaryModel) ?? fallback.primary.id
        primaryEffort = Self.effort(defaults.string(forKey: Key.primaryEffort), default: fallback.primary.effort)
        backupModel = defaults.string(forKey: Key.backupModel) ?? fallback.backup.id
        backupEffort = Self.effort(defaults.string(forKey: Key.backupEffort), default: fallback.backup.effort)
    }

    private static func effort(_ stored: String?, default fallback: String?) -> String? {
        guard let stored else { return fallback }
        return stored == noEffort ? nil : stored
    }

    public var openRouterSettings: OpenRouterClient.Settings {
        var settings = OpenRouterClient.Settings()
        settings.primary = ModelChoice(id: primaryModel, effort: primaryEffort)
        settings.backup = ModelChoice(id: backupModel, effort: backupEffort)
        #if DEBUG
        // UI tests only. Release builds ignore these, so they can't be pointed at another server to catch the key.
        let env = ProcessInfo.processInfo.environment
        if let raw = env["FMW_OPENROUTER_BASE_URL"], let url = URL(string: raw),
           url.scheme == "http" || url.scheme == "https", url.host != nil {
            settings.baseURL = url
        }
        if let raw = env["FMW_OPENROUTER_TIMEOUT"], let seconds = TimeInterval(raw), seconds > 0, seconds <= 600 {
            settings.timeout = seconds
        }
        #endif
        return settings
    }

    public var keychainService: String {
        #if DEBUG
        if let service = ProcessInfo.processInfo.environment["FMW_KEYCHAIN_SERVICE"], !service.isEmpty { return service }
        #endif
        return KeychainStore.defaultService
    }
}
