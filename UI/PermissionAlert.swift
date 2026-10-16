import AppKit

@MainActor
enum PermissionAlert {

    enum Kind {
        case accessibility
        case screenRecording

        fileprivate var title: String {
            switch self {
            case .accessibility: return String(localized: "Accessibility access required")
            case .screenRecording: return String(localized: "Screen Recording access required")
            }
        }

        fileprivate var paneName: String {
            switch self {
            case .accessibility: return String(localized: "Accessibility")
            case .screenRecording: return String(localized: "Screen Recording")
            }
        }

        fileprivate func openSettings() {
            switch self {
            case .accessibility: PermissionsManager.openAccessibilitySettings()
            case .screenRecording: PermissionsManager.openScreenRecordingSettings()
            }
        }
    }

    static func show(_ kind: Kind) {
        let alert = NSAlert()
        alert.messageText = kind.title
        alert.informativeText = String(localized: """
        Steps:
        1. Open System Settings → Privacy & Security → \(kind.paneName)
        2. Make sure LingoPop is in the list and the toggle is ON
        3. Quit LingoPop completely (menu bar → Quit) and relaunch

        macOS only reads the new permission after a full restart of the app.
        """)
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "Open Settings"))
        alert.addButton(withTitle: String(localized: "Quit LingoPop"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            kind.openSettings()
        case .alertSecondButtonReturn:
            NSApp.terminate(nil)
        default:
            break
        }
    }
}
