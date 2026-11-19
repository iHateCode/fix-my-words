import AppKit

/// Where the panel sits relative to the selection. The side (above or below) and the left edge are decided once,
/// for the largest size the panel will reach, so it never jumps while it streams or widens. Every frame is then
/// shifted (never shrunk) into the screen's visible area.
struct PanelPlacement {
    enum Side { case below, above }

    /// `belowY` is the top edge when the panel hangs below the selection; `aboveY` is the bottom edge when it sits above.
    private let belowY: CGFloat
    private let aboveY: CGFloat
    private let anchorPoint: NSPoint
    private let side: Side
    private var x: CGFloat
    /// The fixed edge: the top when `side` is `.below`, the bottom when `.above`.
    private var edgeY: CGFloat

    /// `selectionBounds` is in Accessibility coordinates (origin top-left of the main screen).
    /// Without it the panel hangs off the mouse. `reserving` is the largest size the panel will reach.
    init(selectionBounds: CGRect?, reserving maxSize: NSSize) {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        if let bounds = selectionBounds {
            belowY = mainHeight - bounds.maxY - 8          // AX → AppKit: y = mainScreenHeight - axY - height
            aboveY = mainHeight - bounds.minY + 8
            anchorPoint = NSPoint(x: bounds.minX, y: belowY)
        } else {
            let mouse = NSEvent.mouseLocation
            belowY = mouse.y - 12
            aboveY = mouse.y + 12
            anchorPoint = NSPoint(x: mouse.x + 12, y: belowY)
        }
        let anchor = anchorPoint
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(origin: .zero, size: maxSize)
        let side: Side = belowY - maxSize.height >= visible.minY ? .below : .above
        self.side = side
        edgeY = side == .below ? belowY : aboveY
        // As if already at full width, so widening grows into space known to be free.
        x = max(min(anchorPoint.x, visible.maxX - maxSize.width), visible.minX)
    }

    /// A placement for the same selection as `old` that keeps the old panel where it is, so the command list
    /// hands over to the preview without a jump. The anchor is copied, not re-read, so the mouse fallback stays put.
    init(continuing old: PanelPlacement, from frame: NSRect) {
        self = old
        x = frame.minX
        edgeY = side == .below ? frame.maxY : frame.minY
    }

    /// The frame for `size`: the fixed edge stays put, then all four edges are shifted into the visible frame.
    /// The visible frame is that of the screen holding the anchor, or of the screen holding `current` when the
    /// user has dragged the panel somewhere else.
    func frame(for size: NSSize, current: NSRect? = nil) -> NSRect {
        let origin = NSPoint(x: x, y: side == .below ? edgeY - size.height : edgeY)
        return Self.fitted(NSRect(origin: origin, size: size), on: current ?? NSRect(origin: anchorPoint, size: .zero))
    }

    /// `frame` shifted (never shrunk) into the visible area of the screen that holds `screenOf`.
    static func fitted(_ frame: NSRect, on screenOf: NSRect? = nil) -> NSRect {
        let reference = screenOf ?? frame
        let byOverlap = NSScreen.screens.max { overlap($0.frame, reference) < overlap($1.frame, reference) }
        let screen = byOverlap.flatMap { overlap($0.frame, reference) > 0 ? $0 : nil }
            ?? NSScreen.screens.first { $0.frame.contains(reference.origin) } ?? NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? frame
        var origin = frame.origin
        origin.x = min(max(origin.x, visible.minX), visible.maxX - frame.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - frame.height)
        return NSRect(origin: origin, size: frame.size)
    }

    private static func overlap(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }
}
