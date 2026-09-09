import Foundation

/// Avisa quando a tela é bloqueada e desbloqueada.
///
/// Importa porque declarar atividade acende o display (documentado na man page
/// do `caffeinate`, flag `-u`). Sem pausar com a tela bloqueada, o app
/// reacenderia o monitor a noite toda.
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
