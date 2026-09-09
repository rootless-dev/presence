import Foundation
import OSLog

/// Orchestrates the loop that keeps the idle counter low.
///
/// Every system dependency comes in through a protocol, so the whole loop
/// runs in tests without touching IOKit and without waiting on real time.
@MainActor
public final class PresenceController: ObservableObject {

    /// Interval between loop cycles.
    public static let cycle: TimeInterval = 30
    /// Wait between declaring activity and checking the result.
    static let verifyDelay: TimeInterval = 1
    /// Above this, the counter is considered too high.
    static let idleThreshold: TimeInterval = 5
    /// Consecutive high readings before escalating to synthetic input.
    static let failuresBeforeEscalation = 3

    @Published public private(set) var state: PresenceState = .off
    @Published public private(set) var mode: ActivityMode = .declared
    @Published public private(set) var lastIdle: TimeInterval = 0
    @Published public var autoOff: AutoOffInterval

    /// Notifies when the mode changes, so the app layer can persist the
    /// discovery and the next session already starts in the right mode.
    public var onModeChange: ((ActivityMode) -> Void)?

    private let log = Logger(subsystem: "com.rootless.presence", category: "controller")

    private let declarer: ActivityDeclaring
    private let idleReader: IdleReading
    private let input: SyntheticInputting
    private let date: DateProviding
    private let sleeper: Sleeping
    private let initialMode: ActivityMode

    private var consecutiveHighIdle = 0
    private var startedAt: Date?
    private var hasRequestedPermission = false

    public init(
        declarer: ActivityDeclaring,
        idleReader: IdleReading,
        input: SyntheticInputting,
        date: DateProviding,
        sleeper: Sleeping,
        autoOff: AutoOffInterval,
        initialMode: ActivityMode = .declared
    ) {
        self.declarer = declarer
        self.idleReader = idleReader
        self.input = input
        self.date = date
        self.sleeper = sleeper
        self.autoOff = autoOff
        self.initialMode = initialMode
        self.mode = initialMode
    }

    public func turnOn() {
        state = .active
        mode = initialMode
        consecutiveHighIdle = 0
        hasRequestedPermission = false
        startedAt = date.now
        log.notice("turned on, mode \(String(describing: self.mode), privacy: .public), autoOff \(self.autoOff.rawValue, privacy: .public)")
    }

    public func turnOff() {
        state = .off
        consecutiveHighIdle = 0
        startedAt = nil
        log.notice("turned off")
    }

    public func tick() async {
        guard state == .active || state == .blocked else { return }

        if reachedAutoOff {
            turnOff()
            return
        }

        var declareFailed = false
        do {
            try declarer.declare()
        } catch {
            declareFailed = true
        }

        if mode == .synthetic {
            guard input.isPermitted else {
                requestPermissionOnce()
                state = .blocked
                return
            }
            state = .active
            if !input.tap() {
                log.error("failed to create or post the F15 event")
            }
        }

        await sleeper.sleep(seconds: Self.verifyDelay)

        // The session may have ended during the wait: the user turned it off,
        // or the screen locked. Without this recheck, the in-flight tick
        // resurrects the state and the app ends up claiming to be active with
        // no loop actually running.
        guard state == .active || state == .blocked else { return }

        lastIdle = idleReader.idleSeconds()

        if declareFailed && mode == .declared {
            escalate()
            return
        }

        if lastIdle < Self.idleThreshold {
            consecutiveHighIdle = 0
        } else {
            consecutiveHighIdle += 1
            log.info("idle high: \(self.lastIdle, format: .fixed(precision: 1)) s, failure \(self.consecutiveHighIdle)")
            if consecutiveHighIdle >= Self.failuresBeforeEscalation && mode == .declared {
                escalate()
            }
        }
    }

    /// Switches to injecting real input. If permission isn't granted, it asks
    /// once and assumes `blocked` — the app doesn't pretend to be working.
    private func escalate() {
        mode = .synthetic
        onModeChange?(.synthetic)
        consecutiveHighIdle = 0
        if input.isPermitted {
            state = .active
        } else {
            requestPermissionOnce()
            state = .blocked
        }
        log.notice("escalated to synthetic, state \(String(describing: self.state), privacy: .public)")
    }

    /// The system dialog only appears once per process; asking every cycle
    /// wouldn't bring the dialog back and would just generate noise.
    private func requestPermissionOnce() {
        guard !hasRequestedPermission else { return }
        hasRequestedPermission = true
        input.requestPermission()
    }

    /// Uses wall-clock time, not cycle counting: if the Mac sleeps for three
    /// hours, those three hours count toward the deadline.
    private var reachedAutoOff: Bool {
        guard let startedAt, let limit = autoOff.seconds else { return false }
        return date.now.timeIntervalSince(startedAt) > limit
    }

    /// The screen locked. Declaring activity now would wake the display, and
    /// with the screen locked Teams marks you away anyway — so the loop
    /// pauses. The toggle stays on.
    public func screenLocked() {
        guard state == .active || state == .blocked else { return }
        state = .pausedLocked
    }

    public func screenUnlocked() {
        guard state == .pausedLocked else { return }
        state = .active
    }
}
