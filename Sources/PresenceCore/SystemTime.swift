import Foundation

/// Injectable clock. Auto-off uses wall-clock time, so tests need to be able
/// to jump hours forward without waiting for them.
public protocol DateProviding {
    var now: Date { get }
}

public struct SystemDate: DateProviding {
    public init() {}
    public var now: Date { Date() }
}

/// Injectable delay, so the 1s verification pause doesn't slow down the test
/// suite.
public protocol Sleeping {
    func sleep(seconds: TimeInterval) async
}

public struct SystemSleeper: Sleeping {
    public init() {}
    public func sleep(seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
}
