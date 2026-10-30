import AppKit

@main
enum LingoPopApp {
    @MainActor static let delegate = AppDelegate()

    static func main() {
        // Must run before NSApplication / AppDelegate resolve any localized string.
        AppLanguage.applyAtLaunch()
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}
