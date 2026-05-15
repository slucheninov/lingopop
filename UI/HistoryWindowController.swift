import AppKit
import SwiftUI

@MainActor
final class HistoryWindowController {

    private var window: NSWindow?
    private let store: TranslationHistoryStore

    init(store: TranslationHistoryStore) {
        self.store = store
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: HistoryView(store: store))
        let window = NSWindow(contentViewController: host)
        window.title = "Translation History"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(NSSize(width: 540, height: 480))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
