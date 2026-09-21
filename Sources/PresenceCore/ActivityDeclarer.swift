import Foundation
import IOKit.pwr_mgt

public enum ActivityDeclarerError: Error {
    case ioKitFailure(Int32)
}

/// Declares to the power manager that the user is active.
///
/// It's the same API `caffeinate -u` uses. It requires no macOS permission
/// and injects no input — but, being declarative, there's no documented
/// guarantee it resets `HIDIdleTime`. That's why the app verifies it.
public protocol ActivityDeclaring {
    func declare() throws
}

public final class ActivityDeclarer: ActivityDeclaring {

    private var assertionID = IOPMAssertionID(0)

    public init() {}

    /// Exposed only for the assertion-reuse test.
    public var assertionIDForTesting: UInt32 { assertionID }

    public func declare() throws {
        let name = "Presence: keeping the machine active" as CFString
        let result = IOPMAssertionDeclareUserActivity(name, kIOPMUserActiveLocal, &assertionID)
        guard result == kIOReturnSuccess else {
            throw ActivityDeclarerError.ioKitFailure(result)
        }
    }
}
