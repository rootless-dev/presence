import XCTest
@testable import PresenceCore

final class ActivityDeclarerTests: XCTestCase {

    /// Declaring activity requires no permission at all, so it has to always
    /// work. A failure here means IOKit is unavailable.
    func test_declare_doesNotThrow() {
        let declarer = ActivityDeclarer()
        XCTAssertNoThrow(try declarer.declare())
    }

    /// Repeated calls reuse the same assertion instead of leaking a new one
    /// every cycle. The app calls this every 30s, for hours.
    func test_declare_repeatedReusesAssertion() throws {
        let declarer = ActivityDeclarer()
        try declarer.declare()
        let first = declarer.assertionIDForTesting
        XCTAssertNotEqual(first, 0, "the assertion must have been created and stored")
        try declarer.declare()
        XCTAssertEqual(declarer.assertionIDForTesting, first)
    }
}
