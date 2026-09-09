import XCTest
@testable import PresenceCore

final class IdleReaderTests: XCTestCase {

    /// The reading has to return a plausible value: never negative and never
    /// greater than a day. A value outside that range means we're reading the
    /// wrong key or converting to the wrong unit.
    func test_idleSeconds_returnsPlausibleValue() {
        let reader = IdleReader()
        let value = reader.idleSeconds()
        XCTAssertGreaterThanOrEqual(value, 0)
        XCTAssertLessThan(value, 86_400)
    }

    /// With no input, the counter grows. If there's concurrent human activity
    /// during the test, the value drops — in that case the test is skipped
    /// instead of failing, because the noise isn't a defect in the code.
    func test_idleSeconds_increasesWithoutInput() throws {
        let reader = IdleReader()
        let first = reader.idleSeconds()
        Thread.sleep(forTimeInterval: 2)
        let second = reader.idleSeconds()

        // An environment without an accessible IOHIDSystem (a headless CI
        // runner, for instance) returns 0 on both readings. There's no
        // counter to observe, so there's nothing to assert — and asserting
        // anyway would give a red that speaks about the environment, not the
        // code.
        try XCTSkipIf(first == 0 && second == 0, "IOHIDSystem unavailable in this environment")
        try XCTSkipIf(second < first, "there was human input during the test")
        XCTAssertGreaterThan(second, first)
    }
}
