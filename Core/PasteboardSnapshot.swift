import AppKit

extension NSPasteboard.PasteboardType {
    /// nspasteboard.org conventions: clipboard managers should ignore these writes.
    static let lingoPopTransient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    static let lingoPopConcealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
}

/// Deep copy of the pasteboard contents so they can be restored after LingoPop
/// temporarily uses the clipboard (text capture, Replace).
struct PasteboardSnapshot {
    let items: [NSPasteboardItem]
    /// Plain-text content of the first item at capture time, if any.
    let string: String?

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let copiedItems: [NSPasteboardItem] = pasteboard.pasteboardItems?.map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        } ?? []
        return PasteboardSnapshot(items: copiedItems, string: pasteboard.string(forType: .string))
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            _ = pasteboard.writeObjects(items)
        }
    }

    /// Writes `text` as a temporary clipboard entry marked transient + concealed so
    /// clipboard-history tools skip it. Returns the pasteboard `changeCount` right
    /// after the write, so callers can tell whether someone else wrote afterwards.
    @discardableResult
    static func writeTemporary(_ text: String, to pasteboard: NSPasteboard) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: .lingoPopTransient)
        item.setData(Data(), forType: .lingoPopConcealed)
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }
}
