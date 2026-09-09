import XCTest
@testable import PresenceCore

@MainActor
final class PresenceControllerTests: XCTestCase {

    /// Builds a controller with all dependencies faked. Each test adjusts
    /// whatever it needs on the doubles before calling `tick()`.
    private func makeController(
        idle: [TimeInterval] = [0],
        declarer: FakeDeclarer = FakeDeclarer(),
        input: FakeInput = FakeInput(),
        date: FakeDate = FakeDate(),
        sleeper: Sleeping = NoSleep(),
        autoOff: AutoOffInterval = .never,
        initialMode: ActivityMode = .declared
    ) -> PresenceController {
        PresenceController(
            declarer: declarer,
            idleReader: FakeIdleReader(values: idle),
            input: input,
            date: date,
            sleeper: sleeper,
            autoOff: autoOff,
            initialMode: initialMode
        )
    }

    func test_initialState_isOff() {
        let controller = makeController()
        XCTAssertEqual(controller.state, .off)
        XCTAssertEqual(controller.mode, .declared)
    }

    func test_initialState_usesInjectedMode() {
        let controller = makeController(initialMode: .synthetic)
        XCTAssertEqual(controller.mode, .synthetic)
    }

    func test_turnOn_entersActiveInDeclaredMode() {
        let controller = makeController()
        controller.turnOn()
        XCTAssertEqual(controller.state, .active)
        XCTAssertEqual(controller.mode, .declared)
    }

    /// On a machine where it's already known that declaring isn't enough, the
    /// app starts directly in the mode that works instead of spending 3
    /// cycles rediscovering it.
    func test_turnOn_respectsInjectedInitialMode() {
        let controller = makeController(initialMode: .synthetic)
        controller.turnOn()
        XCTAssertEqual(controller.mode, .synthetic)
    }

    func test_turnOff_returnsToOff() {
        let controller = makeController()
        controller.turnOn()
        controller.turnOff()
        XCTAssertEqual(controller.state, .off)
    }

    func test_tickWhenOff_doesNotDeclareActivity() async {
        let declarer = FakeDeclarer()
        let controller = makeController(declarer: declarer)
        await controller.tick()
        XCTAssertEqual(declarer.callCount, 0)
    }

    func test_tickWhenOn_declaresActivityAndRecordsIdle() async {
        let declarer = FakeDeclarer()
        let controller = makeController(idle: [2], declarer: declarer)
        controller.turnOn()
        await controller.tick()
        XCTAssertEqual(declarer.callCount, 1)
        XCTAssertEqual(controller.lastIdle, 2)
        XCTAssertEqual(controller.state, .active)
    }

    func test_highIdleTwice_doesNotEscalate() async {
        let controller = makeController(idle: [10, 10])
        controller.turnOn()
        await controller.tick()
        await controller.tick()
        XCTAssertEqual(controller.mode, .declared)
    }

    func test_highIdleThreeTimes_escalatesToSynthetic() async {
        let input = FakeInput()
        let controller = makeController(idle: [10, 10, 10], input: input)
        controller.turnOn()
        await controller.tick()
        await controller.tick()
        await controller.tick()
        XCTAssertEqual(controller.mode, .synthetic)
        XCTAssertEqual(controller.state, .active)
    }

    /// A good reading in the middle means declaring is working — the failure
    /// counter resets to zero instead of accumulating across the whole
    /// session.
    func test_goodReadingInTheMiddle_resetsFailureCounter() async {
        let controller = makeController(idle: [10, 10, 0, 10, 10])
        controller.turnOn()
        for _ in 0..<5 { await controller.tick() }
        XCTAssertEqual(controller.mode, .declared)
    }

    /// An IOKit assertion error is a definitive signal, not noise: it
    /// escalates immediately.
    func test_assertionFailure_escalatesImmediately() async {
        let declarer = FakeDeclarer()
        declarer.shouldThrow = true
        let controller = makeController(idle: [0], declarer: declarer)
        controller.turnOn()
        await controller.tick()
        XCTAssertEqual(controller.mode, .synthetic)
    }

    func test_escalateWithoutPermission_goesToBlocked() async {
        let input = FakeInput()
        input.isPermitted = false
        let controller = makeController(idle: [10, 10, 10], input: input)
        controller.turnOn()
        for _ in 0..<3 { await controller.tick() }
        XCTAssertEqual(controller.state, .blocked)
        XCTAssertEqual(input.requestCount, 1)
    }

    /// Granting permission while the app is open has to take effect on its
    /// own, without requiring a restart.
    func test_permissionGrantedLater_returnsToActive() async {
        let input = FakeInput()
        input.isPermitted = false
        let controller = makeController(idle: [10, 10, 10, 10], input: input)
        controller.turnOn()
        for _ in 0..<3 { await controller.tick() }
        XCTAssertEqual(controller.state, .blocked)

        input.isPermitted = true
        await controller.tick()
        XCTAssertEqual(controller.state, .active)
        XCTAssertEqual(input.tapCount, 1)
    }

    /// The discovery that declaring isn't enough has to leave the controller,
    /// otherwise the next session rediscovers it from scratch.
    func test_escalate_notifiesModeChange() async {
        var notified: [ActivityMode] = []
        let controller = makeController(idle: [10, 10, 10])
        controller.onModeChange = { notified.append($0) }
        controller.turnOn()
        for _ in 0..<3 { await controller.tick() }
        XCTAssertEqual(notified, [.synthetic])
    }

    func test_syntheticMode_injectsKeyEachCycle() async {
        let input = FakeInput()
        let controller = makeController(idle: [10, 10, 10, 0, 0], input: input)
        controller.turnOn()
        for _ in 0..<5 { await controller.tick() }
        XCTAssertEqual(controller.mode, .synthetic)
        XCTAssertEqual(input.tapCount, 2)
    }

    /// Real-world scenario: the app was reinstalled, the ad-hoc signature
    /// changed, and macOS revoked Accessibility — but the preferences say to
    /// start in synthetic. Without requesting permission, the app would stay
    /// silent forever.
    func test_startInSyntheticWithoutPermission_requestsPermissionOnce() async {
        let input = FakeInput()
        input.isPermitted = false
        let controller = makeController(idle: [0, 0, 0], input: input, initialMode: .synthetic)
        controller.turnOn()
        for _ in 0..<3 { await controller.tick() }
        XCTAssertEqual(controller.state, .blocked)
        XCTAssertEqual(input.requestCount, 1, "requests once per session, not every cycle")
    }

    /// Restarting after turning off requests permission again — the user may
    /// have granted it in the meantime and want to try again.
    func test_restart_requestsPermissionAgain() async {
        let input = FakeInput()
        input.isPermitted = false
        let controller = makeController(idle: [0, 0], input: input, initialMode: .synthetic)
        controller.turnOn()
        await controller.tick()
        controller.turnOff()
        controller.turnOn()
        await controller.tick()
        XCTAssertEqual(input.requestCount, 2)
    }

    func test_autoOffNever_staysOnAfterDays() async {
        let date = FakeDate()
        let controller = makeController(idle: [0], date: date, autoOff: .never)
        controller.turnOn()
        date.advance(by: 3 * 24 * 3600)
        await controller.tick()
        XCTAssertEqual(controller.state, .active)
    }

    func test_autoOff8h_staysOnBeforeDeadline() async {
        let date = FakeDate()
        let controller = makeController(idle: [0], date: date, autoOff: .hours8)
        controller.turnOn()
        date.advance(by: 7 * 3600)
        await controller.tick()
        XCTAssertEqual(controller.state, .active)
    }

    func test_autoOff8h_turnsOffAfterDeadline() async {
        let date = FakeDate()
        let controller = makeController(idle: [0], date: date, autoOff: .hours8)
        controller.turnOn()
        date.advance(by: 8 * 3600 + 1)
        await controller.tick()
        XCTAssertEqual(controller.state, .off)
    }

    /// The Mac slept for 9 hours with the app on. Upon waking, the deadline
    /// has already passed — counting cycles instead of wall-clock time would
    /// leave the app on.
    func test_autoOff_countsSleepTime() async {
        let date = FakeDate()
        let controller = makeController(idle: [0], date: date, autoOff: .hours8)
        controller.turnOn()
        await controller.tick()
        date.advance(by: 9 * 3600)
        await controller.tick()
        XCTAssertEqual(controller.state, .off)
    }

    /// Restarting resets the countdown from zero.
    func test_restart_resetsDeadline() async {
        let date = FakeDate()
        let controller = makeController(idle: [0], date: date, autoOff: .hour1)
        controller.turnOn()
        date.advance(by: 3601)
        await controller.tick()
        XCTAssertEqual(controller.state, .off)

        controller.turnOn()
        date.advance(by: 60)
        await controller.tick()
        XCTAssertEqual(controller.state, .active)
    }

    func test_lockScreen_pausesWithoutTurningOff() async {
        let declarer = FakeDeclarer()
        let controller = makeController(idle: [0], declarer: declarer)
        controller.turnOn()
        controller.screenLocked()
        XCTAssertEqual(controller.state, .pausedLocked)

        await controller.tick()
        XCTAssertEqual(declarer.callCount, 0, "with the screen locked the loop does not act")
    }

    func test_unlockScreen_resumesOnItsOwn() async {
        let controller = makeController(idle: [0])
        controller.turnOn()
        controller.screenLocked()
        controller.screenUnlocked()
        XCTAssertEqual(controller.state, .active)
    }

    /// Locking the screen with the app off must not turn it on upon
    /// unlocking.
    func test_lockWithAppOff_staysOff() {
        let controller = makeController()
        controller.screenLocked()
        XCTAssertEqual(controller.state, .off)
        controller.screenUnlocked()
        XCTAssertEqual(controller.state, .off)
    }

    /// Locked while in `blocked`? Unlocking returns to `active` and the loop
    /// re-evaluates permission on the next cycle.
    func test_lockWhileWithoutPermission_resumesOnUnlock() async {
        let input = FakeInput()
        input.isPermitted = false
        let controller = makeController(idle: [10, 10, 10], input: input)
        controller.turnOn()
        for _ in 0..<3 { await controller.tick() }
        XCTAssertEqual(controller.state, .blocked)

        controller.screenLocked()
        XCTAssertEqual(controller.state, .pausedLocked)
        controller.screenUnlocked()
        XCTAssertEqual(controller.state, .active)
    }

    /// Turning off during the verification window must not leave the app
    /// claiming it's active — the loop has already been cancelled by the
    /// runner at that point.
    func test_turnOffDuringVerification_doesNotResurrectState() async {
        let declarer = FakeDeclarer()
        declarer.shouldThrow = true
        let spy = SleeperSpy()
        let controller = makeController(idle: [10], declarer: declarer, sleeper: spy)
        controller.turnOn()
        spy.during = { controller.turnOff() }
        await controller.tick()
        XCTAssertEqual(controller.state, .off)
    }

    /// Locking the screen during the verification window must not take the
    /// app out of pause — returning to `.active` would make the loop
    /// reawaken the monitor.
    func test_lockDuringVerification_doesNotResurrectState() async {
        let declarer = FakeDeclarer()
        declarer.shouldThrow = true
        let spy = SleeperSpy()
        let controller = makeController(idle: [10], declarer: declarer, sleeper: spy)
        controller.turnOn()
        spy.during = { controller.screenLocked() }
        await controller.tick()
        XCTAssertEqual(controller.state, .pausedLocked)
    }
}
