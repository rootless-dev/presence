import Foundation

public enum PresenceState: Equatable {
    /// Toggle off. No action.
    case off
    /// Loop running.
    case active
    /// Needs synthetic input, but Accessibility permission hasn't been granted.
    case blocked
    /// Screen locked. The toggle stays on, the loop is suspended.
    case pausedLocked
}

public enum ActivityMode: Equatable {
    /// IOKit power assertion. No permissions required.
    case declared
    /// Synthetic F15 key. Requires Accessibility.
    case synthetic
}

public enum AutoOffInterval: String, CaseIterable, Identifiable {
    case never
    case hour1
    case hours4
    case hours8

    public var id: String { rawValue }

    public var seconds: TimeInterval? {
        switch self {
        case .never: return nil
        case .hour1: return 3600
        case .hours4: return 4 * 3600
        case .hours8: return 8 * 3600
        }
    }

    public var label: String {
        switch self {
        case .never: return "Never"
        case .hour1: return "1 hour"
        case .hours4: return "4 hours"
        case .hours8: return "8 hours"
        }
    }
}
