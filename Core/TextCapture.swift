import AppKit
import Carbon.HIToolbox

struct CapturedText {
    let text: String
    let cursorPosition: NSPoint
}

enum TextCaptureError: Error {
    case emptySelection
    case clipboardTimeout
}

enum TextCapture {

    static func capture() async throws -> CapturedText {
        let cursorPosition = NSEvent.mouseLocation

        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        let savedItems = snapshot(of: pasteboard)

        simulateCommandC()

        let captured = try await waitForClipboardUpdate(
            pasteboard: pasteboard,
            previousChangeCount: previousChangeCount
        )

        restore(items: savedItems, to: pasteboard)

        guard let text = captured, !text.isEmpty else {
            throw TextCaptureError.emptySelection
        }
        return CapturedText(text: text, cursorPosition: cursorPosition)
    }

    private static func simulateCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cKeyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let cKeyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        cKeyDown?.flags = .maskCommand
        cKeyUp?.flags = .maskCommand
        cKeyDown?.post(tap: .cgAnnotatedSessionEventTap)
        cKeyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private static func waitForClipboardUpdate(
        pasteboard: NSPasteboard,
        previousChangeCount: Int,
        timeout: TimeInterval = 0.3,
        pollInterval: TimeInterval = 0.02
    ) async throws -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != previousChangeCount {
                return pasteboard.string(forType: .string)
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        throw TextCaptureError.clipboardTimeout
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        }
    }

    private static func restore(items: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        let restored = items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restored.isEmpty {
            pasteboard.writeObjects(restored)
        }
    }
}
