import XCTest
@testable import PresenceCore

final class PreferencesTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "presence.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func test_default_isEightHours() {
        let prefs = Preferences(defaults: makeDefaults())
        XCTAssertEqual(prefs.autoOff, .hours8)
    }

    func test_writesAndReadsBack() {
        let defaults = makeDefaults()
        Preferences(defaults: defaults).autoOff = .hour1
        XCTAssertEqual(Preferences(defaults: defaults).autoOff, .hour1)
    }

    /// A corrupted value in UserDefaults must not bring the app down.
    func test_invalidValue_fallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set("banana", forKey: "autoOffInterval")
        XCTAssertEqual(Preferences(defaults: defaults).autoOff, .hours8)
    }

    /// With nothing stored, try the cheap, permission-free path first.
    func test_initialMode_defaultIsDeclared() {
        XCTAssertEqual(Preferences(defaults: makeDefaults()).startMode, .declared)
    }

    /// Once it's discovered that declaring isn't enough on this machine, the
    /// next session already starts in the mode that works.
    func test_initialMode_writesAndReadsBack() {
        let defaults = makeDefaults()
        Preferences(defaults: defaults).startMode = .synthetic
        XCTAssertEqual(Preferences(defaults: defaults).startMode, .synthetic)
    }

    /// The app never pauses on its own unless the user asks for it.
    func test_lunch_defaultsToDisabledAtNoon() {
        let prefs = Preferences(defaults: makeDefaults())
        XCTAssertFalse(prefs.lunchEnabled)
        XCTAssertEqual(prefs.lunchStart, TimeOfDay(hour: 12, minute: 0))
        XCTAssertEqual(prefs.lunchEnd, TimeOfDay(hour: 13, minute: 0))
    }

    func test_lunch_writesAndReadsBack() {
        let defaults = makeDefaults()
        let prefs = Preferences(defaults: defaults)
        prefs.lunchEnabled = true
        prefs.lunchStart = TimeOfDay(hour: 11, minute: 45)
        prefs.lunchEnd = TimeOfDay(hour: 13, minute: 5)
        XCTAssertTrue(Preferences(defaults: defaults).lunchEnabled)
        XCTAssertEqual(Preferences(defaults: defaults).lunchStart, TimeOfDay(hour: 11, minute: 45))
        XCTAssertEqual(Preferences(defaults: defaults).lunchEnd, TimeOfDay(hour: 13, minute: 5))
    }

    /// A value outside the day must not pause the app at a random time.
    func test_lunch_invalidValueFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set(5000, forKey: "lunchStart")
        defaults.set(-1, forKey: "lunchEnd")
        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.lunchStart, TimeOfDay(hour: 12, minute: 0))
        XCTAssertEqual(prefs.lunchEnd, TimeOfDay(hour: 13, minute: 0))
    }
}
