import Foundation
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let openCommandList = Self("openCommandList", initial: .init(.w, modifiers: [.command, .shift]))   // `default:` was renamed in 3.0
    static func command(_ id: UUID) -> Self { Self("command-\(id.uuidString)") }
}
