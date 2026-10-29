import AppKit

/// Replace: pastes text back into the previously focused app via a temporary
/// clipboard write + simulated `Cmd+V`, then restores the user's clipboard.
///
/// Create it *before* closing the popup (the initializer snapshots the clipboard and
/// puts `text` on it), then run `paste(into:onSwitchFailed:)` inside a tracked task.
@MainActor
struct TextReplacer {
    private enum Timing {
        /// Delay after closing popup before paste (covers close animation)
        static let pasteDelay: UInt64 = 200_000_000         // 200ms
        /// Best-effort delay after paste before restoring the user's clipboard
        static let clipboardRestoreDelay: UInt64 = 150_000_000 // 150ms
    }

    private let text: String
    private let pasteboard = NSPasteboard.general
    private let snapshot: PasteboardSnapshot
    private let ownChangeCount: Int

    init(text: String) {
        self.text = text
        snapshot = PasteboardSnapshot.capture(from: pasteboard)
        ownChangeCount = PasteboardSnapshot.writeTemporary(text, to: pasteboard)
    }

    /// Activates `targetApp`, pastes, and restores the clipboard. `onSwitchFailed` runs
    /// when the original app could not be brought to the front (nothing was pasted).
    func paste(into targetApp: NSRunningApplication?, onSwitchFailed: () -> Void) async {
        var pasted = false
        defer {
            // Only restore the user's clipboard if nobody wrote to it since our write.
            if pasteboard.changeCount == ownChangeCount {
                if pasted {
                    snapshot.restore(to: pasteboard)
                } else {
                    // Paste failed or was cancelled: leave the text as a normal
                    // (non-transient) clipboard entry so the user can paste manually.
                    pasteboard.clearContents()
                    pasteboard.setString(text, forType: .string)
                }
            }
        }
        do {
            try await Task.sleep(nanoseconds: Timing.pasteDelay)
            guard let targetApp, await activateAndConfirm(targetApp) else {
                onSwitchFailed()
                return
            }
            KeyboardSimulator.simulateCommandV()
            pasted = true
            try await Task.sleep(nanoseconds: Timing.clipboardRestoreDelay)
        } catch {
            // Cancelled. If the paste already went out, `pasted` restores the clipboard.
            return
        }
    }

    /// Activates `app` and polls (up to ~300 ms) until it is actually frontmost.
    private func activateAndConfirm(_ app: NSRunningApplication) async -> Bool {
        let pid = app.processIdentifier
        app.activate(options: .activateIgnoringOtherApps)
        let deadline = Date().addingTimeInterval(0.3)
        while Date() < deadline {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }
}
