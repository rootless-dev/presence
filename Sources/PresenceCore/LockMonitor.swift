import Foundation

/// Notifies when the screen is locked and unlocked.
///
/// This matters because declaring activity wakes the display (documented in
/// the `caffeinate` man page, flag `-u`). Without pausing while the screen is
/// locked, the app would keep waking the monitor all night.
public protocol LockObserving: AnyObject {
    var onLock: (() -> Void)? { get set }
    var onUnlock: (() -> Void)? { get set }
    func start()
}

public final class LockMonitor: LockObserving {

    public var onLock: (() -> Void)?
    public var onUnlock: (() -> Void)?

    public init() {}

    public func start() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onLock?()
        }
        center.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onUnlock?()
        }
    }
}
