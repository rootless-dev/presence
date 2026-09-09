import Foundation

/// Persists the user's choices.
///
/// The on/off state is deliberately **not** persisted: the app always starts
/// off and never turns itself on.
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

    /// The mode the app should start in, based on what's already been
    /// verified on this machine.
    public var startMode: ActivityMode {
        get {
            defaults.string(forKey: Key.startMode) == "synthetic" ? .synthetic : .declared
        }
        set {
            defaults.set(newValue == .synthetic ? "synthetic" : "declared", forKey: Key.startMode)
        }
    }
}
