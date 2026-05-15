import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {

    private var window: NSWindow?
    private let store: SettingsStore
    private let providerImpls: [ProviderType: AIProvider]

    init(store: SettingsStore, providerImpls: [ProviderType: AIProvider]) {
        self.store = store
        self.providerImpls = providerImpls
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingController(rootView: SettingsView(store: store, providerImpls: providerImpls))
        let window = NSWindow(contentViewController: host)
        window.title = "LingoPop Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }
}
