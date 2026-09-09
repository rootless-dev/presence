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
    /// On a break — scheduled lunch or a manual pause. The toggle stays on,
    /// the loop is suspended, and it resumes by itself at the deadline.
    case pausedBreak
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

/// A time of day, with no date attached — what the lunch window is made of.
public struct TimeOfDay: Equatable, Comparable, Sendable {

    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    /// Fails outside the day, so a corrupted preference can't schedule a
    /// break at an hour that doesn't exist.
    public init?(minutesFromMidnight minutes: Int) {
        guard (0..<24 * 60).contains(minutes) else { return nil }
        self.init(hour: minutes / 60, minute: minutes % 60)
    }

    public var minutesFromMidnight: Int { hour * 60 + minute }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesFromMidnight < rhs.minutesFromMidnight
    }
}

/// How long a manual pause lasts.
public enum BreakDuration: Int, CaseIterable, Identifiable {
    case min30 = 30
    case min45 = 45
    case hour1 = 60
    case hour1min30 = 90
    case hours2 = 120

    public var id: Int { rawValue }

    public var seconds: TimeInterval { TimeInterval(rawValue * 60) }

    public var label: String {
        switch self {
        case .min30: return "30 minutes"
        case .min45: return "45 minutes"
        case .hour1: return "1 hour"
        case .hour1min30: return "1 hour 30 min"
        case .hours2: return "2 hours"
        }
    }
}
