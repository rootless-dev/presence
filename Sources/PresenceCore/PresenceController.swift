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
    @Published public var lunchEnabled: Bool
    @Published public var lunchStart: TimeOfDay
    @Published public var lunchEnd: TimeOfDay
    /// When the current break ends, so the menu can say when the app is back.
    @Published public private(set) var breakEndsAt: Date?

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
    private var screenIsLocked = false
    private var manualBreakUntil: Date?
    /// End of a scheduled window the user came back early from, so the
    /// schedule doesn't drag them back in on the next cycle.
    private var skipScheduleUntil: Date?
    private var breakStartedAt: Date?
    /// Time spent on breaks, discounted from the auto-off countdown.
    private var pausedTotal: TimeInterval = 0

    public init(
        declarer: ActivityDeclaring,
        idleReader: IdleReading,
        input: SyntheticInputting,
        date: DateProviding,
        sleeper: Sleeping,
        autoOff: AutoOffInterval,
        initialMode: ActivityMode = .declared,
        lunchEnabled: Bool = false,
        lunchStart: TimeOfDay = TimeOfDay(hour: 12, minute: 0),
        lunchEnd: TimeOfDay = TimeOfDay(hour: 13, minute: 0)
    ) {
        self.declarer = declarer
        self.idleReader = idleReader
        self.input = input
        self.date = date
        self.sleeper = sleeper
        self.autoOff = autoOff
        self.lunchEnabled = lunchEnabled
        self.lunchStart = lunchStart
        self.lunchEnd = lunchEnd
        self.initialMode = initialMode
        self.mode = initialMode
    }

    public func turnOn() {
        state = .active
        mode = initialMode
        consecutiveHighIdle = 0
        hasRequestedPermission = false
        startedAt = date.now
        clearBreak()
        pausedTotal = 0
        skipScheduleUntil = nil
        if let end = breakEnd(at: date.now) {
            beginBreak(endingAt: end)
        }
        log.notice("turned on, mode \(String(describing: self.mode), privacy: .public), autoOff \(self.autoOff.rawValue, privacy: .public)")
    }

    public func turnOff() {
        state = .off
        consecutiveHighIdle = 0
        startedAt = nil
        clearBreak()
        log.notice("turned off")
    }

    public func tick() async {
        guard state == .active || state == .blocked || state == .pausedBreak else { return }

        // The break is evaluated before anything else: while it lasts the app
        // declares nothing and injects nothing, which is the whole point of
        // stepping away for lunch.
        if let end = breakEnd(at: date.now) {
            beginBreak(endingAt: end)
            return
        }
        if state == .pausedBreak {
            endBreak()
        }

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
        // Breaks don't count: "8 hours" means 8 hours of work, so an hour of
        // lunch pushes the deadline an hour further out.
        return date.now.timeIntervalSince(startedAt) - pausedTotal > limit
    }

    /// Starts a manual break of the given length. Useful on the days that
    /// don't match the scheduled lunch.
    public func pause(for duration: BreakDuration) {
        guard state != .off else { return }
        manualBreakUntil = date.now.addingTimeInterval(duration.seconds)
        if let end = breakEnd(at: date.now), state != .pausedLocked {
            beginBreak(endingAt: end)
        }
        log.notice("manual break of \(duration.rawValue, privacy: .public) min")
    }

    /// Ends the current break right away. Skipping a scheduled window only
    /// skips today's — tomorrow's lunch still happens.
    public func resumeNow() {
        if let end = scheduledBreakEnd(at: date.now) {
            skipScheduleUntil = end
        }
        manualBreakUntil = nil
        guard state == .pausedBreak else { return }
        endBreak()
        log.notice("break ended early")
    }

    /// End of the break in effect right now, scheduled or manual, or `nil`
    /// when there is none.
    private func breakEnd(at now: Date) -> Date? {
        let manual = manualBreakUntil.flatMap { $0 > now ? $0 : nil }
        guard let scheduled = scheduledBreakEnd(at: now) else { return manual }
        guard let manual else { return scheduled }
        return max(manual, scheduled)
    }

    /// End of today's lunch window, if `now` falls inside it. The latest
    /// start plus the longest duration still lands on the same day, so the
    /// window never has to be split across midnight.
    /// End of today's lunch window, if `now` falls inside it. An end that
    /// isn't after the start is not a window, so a misconfigured pair can't
    /// pause the app indefinitely.
    private func scheduledBreakEnd(at now: Date) -> Date? {
        guard lunchEnabled, lunchStart < lunchEnd else { return nil }
        let calendar = Calendar.current
        guard let start = calendar.date(
                bySettingHour: lunchStart.hour, minute: lunchStart.minute, second: 0, of: now
              ),
              let end = calendar.date(
                bySettingHour: lunchEnd.hour, minute: lunchEnd.minute, second: 0, of: now
              )
        else { return nil }

        guard now >= start, now < end else { return nil }
        if let skipScheduleUntil, now < skipScheduleUntil { return nil }
        return end
    }

    private func beginBreak(endingAt end: Date) {
        breakEndsAt = end
        guard state != .pausedBreak else { return }
        breakStartedAt = date.now
        state = .pausedBreak
        log.notice("break started, back at \(end, privacy: .public)")
    }

    /// Returns to the loop — or to the lock pause, if the screen is still
    /// locked, since resuming there would only wake the monitor.
    private func endBreak() {
        if let breakStartedAt {
            pausedTotal += date.now.timeIntervalSince(breakStartedAt)
        }
        clearBreak()
        state = screenIsLocked ? .pausedLocked : .active
    }

    private func clearBreak() {
        breakStartedAt = nil
        breakEndsAt = nil
        manualBreakUntil = nil
    }

    /// The screen locked. Declaring activity now would wake the display, and
    /// a machine nobody is sitting at has nothing to stay active for — so
    /// the loop pauses. The toggle stays on.
    public func screenLocked() {
        screenIsLocked = true
        guard state == .active || state == .blocked else { return }
        state = .pausedLocked
    }

    public func screenUnlocked() {
        screenIsLocked = false
        guard state == .pausedLocked else { return }
        state = .active
    }
}
