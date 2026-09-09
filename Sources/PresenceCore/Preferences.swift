import Foundation

/// Persists the user's choices.
///
/// The on/off state is deliberately **not** persisted: the app always starts
/// off and never turns itself on.
public final class Preferences {

    private enum Key {
        static let autoOff = "autoOffInterval"
        static let startMode = "verifiedActivityMode"
        static let lunchEnabled = "lunchEnabled"
        static let lunchStart = "lunchStart"
        static let lunchEnd = "lunchEnd"
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

    /// Off by default: the app only steps aside when the user asks it to.
    public var lunchEnabled: Bool {
        get { defaults.bool(forKey: Key.lunchEnabled) }
        set { defaults.set(newValue, forKey: Key.lunchEnabled) }
    }

    public var lunchStart: TimeOfDay {
        get { time(forKey: Key.lunchStart) ?? TimeOfDay(hour: 12, minute: 0) }
        set { defaults.set(newValue.minutesFromMidnight, forKey: Key.lunchStart) }
    }

    public var lunchEnd: TimeOfDay {
        get { time(forKey: Key.lunchEnd) ?? TimeOfDay(hour: 13, minute: 0) }
        set { defaults.set(newValue.minutesFromMidnight, forKey: Key.lunchEnd) }
    }

    private func time(forKey key: String) -> TimeOfDay? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return TimeOfDay(minutesFromMidnight: defaults.integer(forKey: key))
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
