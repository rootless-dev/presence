import Foundation
import IOKit
import OSLog

/// Reads the system's input idle counter.
///
/// It's the same value `ioreg -c IOHIDSystem | grep HIDIdleTime` shows, in
/// nanoseconds, and it's the number Teams checks to decide whether you're
/// away.
public protocol IdleReading {
    func idleSeconds() -> TimeInterval
}

public struct IdleReader: IdleReading {

    private let log = Logger(subsystem: "com.rootless.presence", category: "idle")

    public init() {}

    public func idleSeconds() -> TimeInterval {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOHIDSystem")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            log.error("IOHIDSystem unavailable: IOServiceGetMatchingServices failed")
            return 0
        }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else {
            log.error("IOHIDSystem has no registry entry")
            return 0
        }
        defer { IOObjectRelease(entry) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any],
              let nanoseconds = properties["HIDIdleTime"] as? NSNumber
        else {
            log.error("HIDIdleTime property missing or unreadable")
            return 0
        }

        return nanoseconds.doubleValue / 1_000_000_000
    }
}
