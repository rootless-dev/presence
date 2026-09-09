import ServiceManagement

/// Registra o app para abrir junto com o sistema.
///
/// `SMAppService.mainApp` guarda a localização do bundle. Registrado a partir
/// de `.build/release`, o login item quebra assim que a pasta some — por isso
/// o alvo `install` do Makefile copia para `/Applications` antes.
enum LoginItem {

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
            return false
        }
    }
}
