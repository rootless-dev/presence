import Foundation
import IOKit

/// Lê o contador de inatividade de input do sistema.
///
/// É o mesmo valor que `ioreg -c IOHIDSystem | grep HIDIdleTime` mostra, em
/// nanossegundos, e é o número que o Teams consulta para decidir se você está
/// ausente.
public protocol IdleReading {
    func idleSeconds() -> TimeInterval
}

public struct IdleReader: IdleReading {

    public init() {}

    public func idleSeconds() -> TimeInterval {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOHIDSystem")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return 0
        }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any],
              let nanoseconds = properties["HIDIdleTime"] as? NSNumber
        else {
            return 0
        }

        return nanoseconds.doubleValue / 1_000_000_000
    }
}
