import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let store: SettingsStore
    private let usageStore: UsageStore
    private let providerImpls: [ProviderType: AIProvider]

    init(store: SettingsStore, usageStore: UsageStore, providerImpls: [ProviderType: AIProvider]) {
        self.store = store
        self.usageStore = usageStore
        self.providerImpls = providerImpls
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingController(rootView: SettingsView(
            store: store,
            usageStore: usageStore,
            providerImpls: providerImpls
        ))
        let window = NSWindow(contentViewController: host)
        window.title = "LingoPop Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
