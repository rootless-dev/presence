import Foundation

/// Relógio injetável. O auto-off usa tempo de parede, então os testes precisam
/// conseguir saltar horas sem esperar por elas.
public protocol DateProviding {
    var now: Date { get }
}

public struct SystemDate: DateProviding {
    public init() {}
    public var now: Date { Date() }
}

/// Espera injetável, para que a pausa de verificação de 1s não deixe a suíte
/// de testes lenta.
public protocol Sleeping {
    func sleep(seconds: TimeInterval) async
}

public struct SystemSleeper: Sleeping {
    public init() {}
    public func sleep(seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
