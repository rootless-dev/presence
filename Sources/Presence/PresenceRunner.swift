import AppKit
import Foundation
import PresenceCore

/// Owns the loop: turns on, turns off, and keeps the 30s cadence.
///
/// Lives in the app layer, not in `PresenceCore`, because it deals with the
/// process lifecycle (App Nap) — something the controller's tests shouldn't
/// even have to see.
@MainActor
final class PresenceRunner {

    let controller: PresenceController

    private let lockMonitor: LockObserving
    private let preferences: Preferences
    private var loop: Task<Void, Never>?
    private var activityToken: NSObjectProtocol?

    init(controller: PresenceController, lockMonitor: LockObserving, preferences: Preferences) {
        self.controller = controller
        self.lockMonitor = lockMonitor
        self.preferences = preferences
    }

    func start() {
        controller.onModeChange = { [weak self] mode in self?.preferences.startMode = mode }
        lockMonitor.onLock = { [weak self] in self?.controller.screenLocked() }
        lockMonitor.onUnlock = { [weak self] in self?.controller.screenUnlocked() }
        lockMonitor.start()
    }

    func toggle() {
        controller.state == .off ? turnOn() : turnOff()
    }

    func setAutoOff(_ interval: AutoOffInterval) {
        controller.autoOff = interval
        preferences.autoOff = interval
    }

    func setLunchEnabled(_ enabled: Bool) {
        controller.lunchEnabled = enabled
        preferences.lunchEnabled = enabled
    }

    func setLunchStart(_ start: TimeOfDay) {
        controller.lunchStart = start
        preferences.lunchStart = start
    }

    func setLunchEnd(_ end: TimeOfDay) {
        controller.lunchEnd = end
        preferences.lunchEnd = end
    }

    private func turnOn() {
        controller.turnOn()

        // Without this, App Nap coalesces the timers of a backgrounded menu
        // bar app, and a 30s cycle can turn into minutes — plenty of time
        // for Teams to go yellow before the next tick.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Presence keeping status available"
        )

        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.controller.tick()
                // Auto-off turns itself off internally; the runner just notices.
                if self.controller.state == .off {
                    self.turnOff()
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(PresenceController.cycle * 1_000_000_000))
            }
        }
    }

    private func turnOff() {
        loop?.cancel()
        loop = nil
        controller.turnOff()
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
        }
        activityToken = nil
    }
}
