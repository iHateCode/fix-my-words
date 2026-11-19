import AppKit

/// Every item and type on a pasteboard, copied into memory so it can be put back after a ⌘C or ⌘V.
@MainActor
struct ClipboardSnapshot {
    static let maxTypeSize = 50 * 1024 * 1024        // a huge copied image can't stall the app
    private let items: [[(type: NSPasteboard.PasteboardType, data: Data)]]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in
                guard let data = item.data(forType: type), data.count <= Self.maxTypeSize else { return nil }
                return (type, data)
            }
        }
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored: [NSPasteboardItem] = items.compactMap { types in
            guard !types.isEmpty else { return nil }
            let item = NSPasteboardItem()
            for (type, data) in types { item.setData(data, forType: type) }
            return item
        }
        if !restored.isEmpty { pasteboard.writeObjects(restored) }
    }
}
