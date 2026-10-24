import Foundation
import ServiceManagement

final class LaunchAtLoginManager {
    static let shared = LaunchAtLoginManager()

    private init() {}

    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    func setEnabled(_ enabled: Bool) -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    if SMAppService.mainApp.status != .enabled {
                        try SMAppService.mainApp.register()
                        Logger.log("[LaunchAtLogin] Registered mainApp service successfully.")
                    }
                } else {
                    if SMAppService.mainApp.status == .enabled {
                        try SMAppService.mainApp.unregister()
                        Logger.log("[LaunchAtLogin] Unregistered mainApp service.")
                    }
                }
                return true
            } catch {
                Logger.log("[LaunchAtLogin] Failed to change login item state: %@", error.localizedDescription)
                return false
            }
        }
        return false
    }
}
