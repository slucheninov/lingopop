import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let store: SettingsStore
    private let usageStore: UsageStore
    private let providerImpls: [ProviderType: AIProvider]
    private let navigation = SettingsNavigation()

    init(store: SettingsStore, usageStore: UsageStore, providerImpls: [ProviderType: AIProvider]) {
        self.store = store
        self.usageStore = usageStore
        self.providerImpls = providerImpls
    }

    /// Shows the Settings window, switching to `tab` when given (also if already open).
    func show(tab: SettingsTab? = nil) {
        if let tab { navigation.tab = tab }
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingController(rootView: SettingsView(
            navigation: navigation,
            store: store,
            usageStore: usageStore,
            providerImpls: providerImpls
        ))
        let window = NSWindow(contentViewController: host)
        window.title = String(localized: "LingoPop Settings")
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
        navigation.tab = .main
    }
}
