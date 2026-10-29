import AppKit

@main
enum LingoPopApp {
    @MainActor static let delegate = AppDelegate()

    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            app.delegate = delegate
            app.setActivationPolicy(.accessory)
            app.run()
        }
    }
}
