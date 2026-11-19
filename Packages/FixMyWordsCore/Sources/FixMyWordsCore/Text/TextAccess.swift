import AppKit

/// Everything the app needs from the outside world's text boxes. The UI tests drive the real one;
/// nothing else depends on the concrete types.
@MainActor
public protocol TextAccess {
    func capture() async throws -> Capture
    func paste(_ text: String, into target: FocusSnapshot) async throws
    func currentFocus() -> FocusSnapshot?
    /// True while a capture's ⌘C or a paste has the clipboard swapped out, so nothing else may touch it.
    var isUsingClipboard: Bool { get }
}

public struct Capture: Sendable {
    public let text: String
    public let focus: FocusSnapshot
    public let selectionBounds: CGRect?      // screen rect of the selection, nil if unknown
    public let method: Method
    public enum Method: Sendable { case accessibility, clipboard }
}

/// Which text box had focus. `element` is nil when Accessibility couldn't see one.
public struct FocusSnapshot: @unchecked Sendable {   // AXUIElement is a CF type; only touched on the main actor
    public let pid: pid_t
    public let windowNumber: Int?
    public let windowTitle: String?          // in Chrome this is the tab's title; memory only, never logged
    public let element: AXUIElement?

    public func isSameTarget(as other: FocusSnapshot) -> Bool {
        guard pid == other.pid else { return false }
        if let a = element, let b = other.element { return CFEqual(a, b) }
        guard let number = windowNumber, let title = windowTitle else { return false }   // can't confirm: Copy only
        return number == other.windowNumber && title == other.windowTitle
    }
}

public enum CaptureError: Error, Equatable {
    case noPermission          // Accessibility not granted, or revoked after an update
    case nothingSelected
    case copyTimedOut
}
