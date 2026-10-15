import AppKit
import HotKey
import Carbon.HIToolbox

struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifierFlags: UInt

    static let `default` = HotkeyConfig(
        keyCode: UInt32(kVK_ANSI_T),
        modifierFlags: NSEvent.ModifierFlags.option.rawValue
    )

    static let empty = HotkeyConfig(keyCode: 0, modifierFlags: 0)

    var isEmpty: Bool { keyCode == 0 && modifierFlags == 0 }

    var modifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlags)
    }

    var hotKeyKey: Key? {
        Key(carbonKeyCode: keyCode)
    }

    var displayString: String {
        if isEmpty { return "Not set" }
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        if let key = hotKeyKey {
            parts.append(String(describing: key).uppercased())
        } else {
            parts.append("?")
        }
        return parts.joined()
    }
}
