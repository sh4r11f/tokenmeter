import ServiceManagement
import os.log

enum LaunchAtLogin {
    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            os_log("TokenMeter: failed to %{public}@ launch-at-login: %{public}@",
                   enabled ? "register" : "unregister", String(describing: error))
        }
    }
}
