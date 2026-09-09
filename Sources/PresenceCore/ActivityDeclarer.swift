import Foundation
import IOKit.pwr_mgt

public enum ActivityDeclarerError: Error {
    case ioKitFailure(Int32)
}

/// Declara ao gerenciador de energia que o usuário está ativo.
///
/// É a mesma API que o `caffeinate -u` usa. Não exige permissão nenhuma do
/// macOS e não injeta input — mas, por ser declarativa, não há garantia
/// documentada de que zere o `HIDIdleTime`. Por isso o app verifica.
public protocol ActivityDeclaring {
    func declare() throws
}

public final class ActivityDeclarer: ActivityDeclaring {

    private var assertionID = IOPMAssertionID(0)

    public init() {}

    /// Exposto apenas para o teste de reaproveitamento da assertion.
    public var assertionIDForTesting: UInt32 { assertionID }

    public func declare() throws {
        let name = "Presence: mantendo status disponível" as CFString
        let result = IOPMAssertionDeclareUserActivity(name, kIOPMUserActiveLocal, &assertionID)
        guard result == kIOReturnSuccess else {
            throw ActivityDeclarerError.ioKitFailure(result)
        }
    }
}
