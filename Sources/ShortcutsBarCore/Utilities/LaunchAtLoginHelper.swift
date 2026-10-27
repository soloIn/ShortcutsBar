import Foundation
import ServiceManagement

public enum LaunchAtLoginHelper {
    public static var isEnabled: Bool {
        return SMAppService.mainApp.status == .enabled
    }

    public static func setEnabled(_ enabled: Bool) {
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
            NSLog("LaunchAtLogin failed: \(error)")
        }
    }
}
