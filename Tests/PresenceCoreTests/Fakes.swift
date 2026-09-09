import Foundation
@testable import PresenceCore

final class FakeDeclarer: ActivityDeclaring {
    var shouldThrow = false
    private(set) var callCount = 0

    func declare() throws {
        callCount += 1
        if shouldThrow { throw ActivityDeclarerError.ioKitFailure(-1) }
    }
}

/// Returns the values in the given order; repeats the last one once the list runs out.
final class FakeIdleReader: IdleReading {
    var values: [TimeInterval]
    private var index = 0

    init(values: [TimeInterval]) { self.values = values }

    func idleSeconds() -> TimeInterval {
        let value = values[min(index, values.count - 1)]
        index += 1
        return value
    }
}

final class FakeInput: SyntheticInputting {
    var isPermitted = true
    private(set) var tapCount = 0
    private(set) var requestCount = 0
    private(set) var openSettingsCount = 0

    func tap() -> Bool { tapCount += 1; return true }
    func requestPermission() { requestCount += 1 }
    func openPermissionSettings() { openSettingsCount += 1 }
}

final class FakeDate: DateProviding {
    var now: Date

    init(now: Date = Date(timeIntervalSince1970: 1_000_000)) { self.now = now }

    func advance(by seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

struct NoSleep: Sleeping {
    func sleep(seconds: TimeInterval) async {}
}

/// A `Sleeping` double that runs a closure during the wait, to simulate a
/// state mutation that happens while a `tick()` is in flight — something
/// `NoSleep` (with no real suspension) cannot interleave reliably.
@MainActor
final class SleeperSpy: Sleeping {
    var during: () -> Void = {}

    func sleep(seconds: TimeInterval) async {
        during()
    }
}
