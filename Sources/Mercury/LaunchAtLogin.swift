import Foundation
import ServiceManagement

/// Wraps SMAppService's "register the main app itself as a login item"
/// API (macOS 13+) — no separate helper executable needed.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("LaunchAtLogin: failed to update status: \(error)")
        }
    }
}
