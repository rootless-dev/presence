import XCTest
@testable import PresenceCore

/// Covers the lunch break: the scheduled daily window and the manual
/// "pause for N" the menu offers.
@MainActor
final class BreakTests: XCTestCase {

    /// A date at the given time of day, in the machine's own calendar, so the
    /// window maths is checked the same way wherever the suite runs.
    private func at(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: Date(timeIntervalSince1970: 1_000_000)
        )!
    }

    private func makeController(
        now: Date,
        idle: [TimeInterval] = [0],
        declarer: FakeDeclarer = FakeDeclarer(),
        date: FakeDate? = nil,
        autoOff: AutoOffInterval = .never,
        lunchEnabled: Bool = true,
        lunchStart: TimeOfDay = TimeOfDay(hour: 12, minute: 0),
        lunchEnd: TimeOfDay = TimeOfDay(hour: 13, minute: 0)
    ) -> PresenceController {
        PresenceController(
            declarer: declarer,
            idleReader: FakeIdleReader(values: idle),
            input: FakeInput(),
            date: date ?? FakeDate(now: now),
            sleeper: NoSleep(),
            autoOff: autoOff,
            initialMode: .declared,
            lunchEnabled: lunchEnabled,
            lunchStart: lunchStart,
            lunchEnd: lunchEnd
        )
    }

    // MARK: - Scheduled window

    func test_insideLunchWindow_pausesTheLoop() async {
        let declarer = FakeDeclarer()
        let controller = makeController(now: at(12, 30), declarer: declarer)
        controller.turnOn()
        await controller.tick()
        XCTAssertEqual(controller.state, .pausedBreak)
        XCTAssertEqual(declarer.callCount, 0, "during the break the loop does not act")
    }

    func test_turnOnDuringLunch_startsPaused() {
        let controller = makeController(now: at(12, 30))
        controller.turnOn()
        XCTAssertEqual(controller.state, .pausedBreak)
    }

    func test_lunchDisabled_neverPauses() async {
        let controller = makeController(now: at(12, 30), lunchEnabled: false)
        controller.turnOn()
        await controller.tick()
        XCTAssertEqual(controller.state, .active)
    }

    /// An end that isn't after the start is not a window — the app keeps
    /// working instead of pausing forever.
    func test_endNotAfterStart_neverPauses() async {
        let controller = makeController(
            now: at(12, 30),
            lunchStart: TimeOfDay(hour: 13, minute: 0),
            lunchEnd: TimeOfDay(hour: 12, minute: 0)
        )
        controller.turnOn()
        await controller.tick()
        XCTAssertEqual(controller.state, .active)
    }

    /// Any minute goes, not just half-hour marks.
    func test_windowOnOddMinutes_isRespected() async {
        let date = FakeDate(now: at(12, 10))
        let controller = makeController(
            now: at(12, 10),
            idle: [0, 0, 0],
            date: date,
            lunchStart: TimeOfDay(hour: 12, minute: 15),
            lunchEnd: TimeOfDay(hour: 13, minute: 5)
        )
        controller.turnOn()
        await controller.tick()
        XCTAssertEqual(controller.state, .active)

        date.now = at(12, 20)
        await controller.tick()
        XCTAssertEqual(controller.state, .pausedBreak)

        date.now = at(13, 10)
        await controller.tick()
        XCTAssertEqual(controller.state, .active)
    }

    func test_crossingIntoTheWindow_entersBreak() async {
        let date = FakeDate(now: at(11, 59))
        let controller = makeController(now: at(11, 59), idle: [0, 0], date: date)
        controller.turnOn()
        await controller.tick()
        XCTAssertEqual(controller.state, .active)

        date.advance(by: 120)
        await controller.tick()
        XCTAssertEqual(controller.state, .pausedBreak)
    }

    func test_windowEnds_resumesOnItsOwn() async {
        let declarer = FakeDeclarer()
        let date = FakeDate(now: at(12, 30))
        let controller = makeController(now: at(12, 30), idle: [0, 0], declarer: declarer, date: date)
        controller.turnOn()
        await controller.tick()
        XCTAssertEqual(controller.state, .pausedBreak)

        date.advance(by: 31 * 60)
        await controller.tick()
        XCTAssertEqual(controller.state, .active)
        XCTAssertEqual(declarer.callCount, 1)
    }

    /// Resuming with the screen still locked would wake the monitor — the
    /// break hands over to the lock pause, not to the loop.
    func test_windowEndsWithScreenLocked_staysPaused() async {
        let date = FakeDate(now: at(12, 30))
        let controller = makeController(now: at(12, 30), idle: [0, 0], date: date)
        controller.turnOn()
        await controller.tick()
        controller.screenLocked()

        date.advance(by: 31 * 60)
        await controller.tick()
        XCTAssertEqual(controller.state, .pausedLocked)
    }

    /// The menu shows when the app comes back; without the deadline it could
    /// only say "paused".
    func test_breakEndsAt_reportsWhenItResumes() async {
        let controller = makeController(now: at(12, 30))
        controller.turnOn()
        await controller.tick()
        XCTAssertEqual(controller.breakEndsAt, at(13, 0))
    }

    func test_turnOff_clearsTheBreak() async {
        let controller = makeController(now: at(12, 30))
        controller.turnOn()
        await controller.tick()
        controller.turnOff()
        XCTAssertEqual(controller.state, .off)
        XCTAssertNil(controller.breakEndsAt)
    }

    // MARK: - Manual pause

    func test_manualPause_suspendsTheLoop() async {
        let declarer = FakeDeclarer()
        let controller = makeController(now: at(9, 0), declarer: declarer, lunchEnabled: false)
        controller.turnOn()
        controller.pause(for: .hour1)
        XCTAssertEqual(controller.state, .pausedBreak)

        await controller.tick()
        XCTAssertEqual(declarer.callCount, 0)
    }

    func test_manualPause_expiresOnItsOwn() async {
        let date = FakeDate(now: at(9, 0))
        let controller = makeController(now: at(9, 0), idle: [0], date: date, lunchEnabled: false)
        controller.turnOn()
        controller.pause(for: .min30)

        date.advance(by: 31 * 60)
        await controller.tick()
        XCTAssertEqual(controller.state, .active)
    }

    func test_resumeNow_cancelsTheManualPause() {
        let controller = makeController(now: at(9, 0), lunchEnabled: false)
        controller.turnOn()
        controller.pause(for: .hours2)
        controller.resumeNow()
        XCTAssertEqual(controller.state, .active)
    }

    /// Coming back early from lunch must not be undone by the schedule on the
    /// very next cycle.
    func test_resumeNow_duringScheduledLunch_doesNotReenter() async {
        let date = FakeDate(now: at(12, 10))
        let controller = makeController(now: at(12, 10), idle: [0, 0], date: date)
        controller.turnOn()
        XCTAssertEqual(controller.state, .pausedBreak)

        controller.resumeNow()
        await controller.tick()
        XCTAssertEqual(controller.state, .active)

        date.advance(by: 10 * 60)
        await controller.tick()
        XCTAssertEqual(controller.state, .active, "the skipped window stays skipped")
    }

    /// The next day's window is a new window — skipping today's must not
    /// disable the schedule for good.
    func test_resumeNow_doesNotSkipTheNextDay() async {
        let date = FakeDate(now: at(12, 10))
        let controller = makeController(now: at(12, 10), idle: [0, 0], date: date)
        controller.turnOn()
        controller.resumeNow()

        date.advance(by: 24 * 3600)
        await controller.tick()
        XCTAssertEqual(controller.state, .pausedBreak)
    }

    // MARK: - Auto-off

    /// Eight hours means eight hours of work: the lunch break pushes the
    /// deadline back instead of eating into it.
    func test_autoOff_doesNotCountTheBreak() async {
        let date = FakeDate(now: at(9, 0))
        let controller = makeController(
            now: at(9, 0),
            idle: [0, 0, 0, 0],
            date: date,
            autoOff: .hours8
        )
        controller.turnOn()

        date.now = at(12, 30)
        await controller.tick()
        XCTAssertEqual(controller.state, .pausedBreak)

        date.now = at(13, 30)
        await controller.tick()
        XCTAssertEqual(controller.state, .active)

        date.now = at(17, 30)
        await controller.tick()
        XCTAssertEqual(controller.state, .active, "an hour of lunch buys an extra hour")

        date.now = at(18, 30)
        await controller.tick()
        XCTAssertEqual(controller.state, .off)
    }
}
