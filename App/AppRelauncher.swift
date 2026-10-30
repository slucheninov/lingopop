import AppKit
import os

/// Relaunches the app cleanly (used after the UI language changes).
///
/// A detached shell waits until this process has exited, then opens the bundle again,
/// so the old and new instances never overlap (global hotkeys would otherwise clash).
@MainActor
enum AppRelauncher {
    private static let log = Logger(subsystem: "com.lingopop.app", category: "relaunch")

    /// Returns `false` (and does not quit) if the helper could not be spawned.
    @discardableResult
    static func relaunch() -> Bool {
        let script = """
        i=0
        while kill -0 "$1" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done
        kill -0 "$1" 2>/dev/null && exit 1
        exec /usr/bin/open -n "$2"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundlePath]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            log.error("relaunch helper failed: \(error.localizedDescription, privacy: .public)")
            showFailureAlert()
            return false
        }
        NSApp.terminate(nil)
        return true
    }

    private static func showFailureAlert() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Could not relaunch LingoPop")
        alert.informativeText = String(localized: "Quit LingoPop from the menu bar and open it again to apply the new language.")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "OK"))
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
