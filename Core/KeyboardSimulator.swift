import AppKit
import Carbon.HIToolbox

/// Synthesises keyboard events for the frontmost app (requires Accessibility).
enum KeyboardSimulator {

    static func post(key: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    static func simulateCommandC() {
        post(key: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)
    }

    static func simulateCommandV() {
        post(key: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
    }
}
