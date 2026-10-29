import AppKit
import HotKey
import os

@MainActor
final class HotkeyManager {

    private var hotKeys: [AIOperation: HotKey] = [:]
    var onTrigger: ((AIOperation) -> Void)?
    private let log = Logger(subsystem: "com.lingopop.app", category: "HotkeyManager")

    func apply(_ configs: [AIOperation: HotkeyConfig]) {
        hotKeys.removeAll()
        for (operation, config) in configs {
            guard let key = config.hotKeyKey else {
                log.error("apply \(operation.rawValue, privacy: .public): Key(carbonKeyCode: \(config.keyCode, privacy: .public)) returned nil")
                continue
            }
            let hk = HotKey(key: key, modifiers: config.modifiers)
            hk.keyDownHandler = { [weak self] in
                self?.log.info("hotkey fired: \(operation.rawValue, privacy: .public)")
                self?.onTrigger?(operation)
            }
            hotKeys[operation] = hk
            log.info("apply \(operation.rawValue, privacy: .public): key=\(String(describing: key), privacy: .public) mods=\(config.modifierFlags, privacy: .public)")
        }
    }
}
