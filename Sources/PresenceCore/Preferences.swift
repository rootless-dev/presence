import Foundation

/// Persiste as escolhas do usuário.
///
/// O estado ligado/desligado é deliberadamente **não** persistido: o app sempre
/// inicia desligado e nunca liga sozinho.
public final class Preferences {

    private enum Key {
        static let autoOff = "autoOffInterval"
        static let startMode = "verifiedActivityMode"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var autoOff: AutoOffInterval {
        get {
            guard let raw = defaults.string(forKey: Key.autoOff),
                  let value = AutoOffInterval(rawValue: raw)
            else {
                return .hours8
            }
            return value
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.autoOff)
        }
    }

    /// O modo em que o app deve começar, com base no que já foi verificado
    /// nesta máquina.
    public var startMode: ActivityMode {
        get {
            defaults.string(forKey: Key.startMode) == "synthetic" ? .synthetic : .declared
        }
        set {
            defaults.set(newValue == .synthetic ? "synthetic" : "declared", forKey: Key.startMode)
        }
    }
}
