import AppKit

struct CapturedText {
    let text: String
    let cursorPosition: NSPoint
}

enum TextCaptureError: LocalizedError {
    case emptySelection
    case clipboardTimeout

    var errorDescription: String? {
        switch self {
        case .emptySelection:
            return "Nothing selected. Select some text first, then press the hotkey."
        case .clipboardTimeout:
            return "Clipboard didn't update in time. Try again."
        }
    }
}

enum TextCapture {

    static func capture() async throws -> CapturedText {
        let cursorPosition = NSEvent.mouseLocation

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        // Sentinel: put a unique marker on the clipboard before Cmd+C. If it is
        // still there after the poll, the copy produced nothing (no selection);
        // anything else is real selected text, even if identical to the old clipboard.
        let marker = "LingoPop-capture-" + UUID().uuidString
        let markerChangeCount = PasteboardSnapshot.writeTemporary(marker, to: pasteboard)

        // Latest changeCount we know we produced (marker, then the copy result).
        // Only restore the user's clipboard if nobody else has written since; this
        // also covers cancellation / timeout while the marker is still on the board.
        var observedChangeCount = markerChangeCount
        defer {
            if pasteboard.changeCount == observedChangeCount {
                snapshot.restore(to: pasteboard)
            }
        }

        KeyboardSimulator.simulateCommandC()

        let update: (text: String?, changeCount: Int)
        do {
            update = try await waitForClipboardUpdate(
                pasteboard: pasteboard,
                previousChangeCount: markerChangeCount
            )
        } catch TextCaptureError.clipboardTimeout {
            if pasteboard.string(forType: .string) == marker {
                throw TextCaptureError.emptySelection
            }
            throw TextCaptureError.clipboardTimeout
        }
        observedChangeCount = update.changeCount

        guard let text = update.text, !text.isEmpty, text != marker else {
            throw TextCaptureError.emptySelection
        }
        return CapturedText(text: text, cursorPosition: cursorPosition)
    }

    private enum Timing {
        /// Polling timeout waiting for clipboard change after Cmd+C
        static let clipboardPollTimeout: UInt64 = 300_000_000  // 300ms
        /// Interval between clipboard change-count polls
        static let clipboardPollInterval: UInt64 = 10_000_000  // 10ms
    }

    private static func waitForClipboardUpdate(
        pasteboard: NSPasteboard,
        previousChangeCount: Int
    ) async throws -> (text: String?, changeCount: Int) {
        let deadline = Date().addingTimeInterval(Double(Timing.clipboardPollTimeout) / 1_000_000_000)
        while Date() < deadline {
            let count = pasteboard.changeCount
            if count != previousChangeCount {
                return (pasteboard.string(forType: .string), count)
            }
            try await Task.sleep(nanoseconds: Timing.clipboardPollInterval)
        }
        // Final re-check: a copy that landed right at the deadline must not be lost
        // (or clobbered by a restore).
        let count = pasteboard.changeCount
        if count != previousChangeCount {
            return (pasteboard.string(forType: .string), count)
        }
        throw TextCaptureError.clipboardTimeout
    }
}
