import OSLog
import ServiceManagement

/// Registra o app para abrir junto com o sistema.
///
/// `SMAppService.mainApp` guarda a localização do bundle. Registrado a partir
/// de `.build/release`, o login item quebra assim que a pasta some — por isso
/// o alvo `install` do Makefile copia para `/Applications` antes.
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
            let action = enabled ? "registro" : "cancelamento"
            log.error("falha no \(action, privacy: .public) do login item: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
