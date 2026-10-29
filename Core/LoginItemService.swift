import Foundation
import ServiceManagement
import os

enum LoginItemService {

    private static let log = Logger(subsystem: "com.lingopop.app", category: "LoginItem")

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            log.error("LoginItem toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
