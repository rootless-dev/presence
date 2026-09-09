import OSLog
import ServiceManagement

/// Registers the app to launch alongside the system.
///
/// `SMAppService.mainApp` stores the bundle's location. Registered from
/// `.build/release`, the login item breaks as soon as that folder disappears
/// — which is why the Makefile's `install` target copies to `/Applications`
/// first.
enum LoginItem {

    private static let log = Logger(subsystem: "com.rootless.presence", category: "loginItem")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            let action = enabled ? "registration" : "unregistration"
            log.error("login item \(action, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
