import AppKit
import Foundation
import PresenceCore

/// Dono do laço: liga, desliga e mantém o ritmo de 30s.
///
/// Fica na camada de app, não no `PresenceCore`, porque lida com o ciclo de
/// vida do processo (App Nap) — coisa que os testes do controller não deveriam
/// nem enxergar.
@MainActor
final class PresenceRunner {

    let controller: PresenceController

    private let lockMonitor: LockObserving
    private let preferences: Preferences
    private var loop: Task<Void, Never>?
    private var activityToken: NSObjectProtocol?

    init(controller: PresenceController, lockMonitor: LockObserving, preferences: Preferences) {
        self.controller = controller
        self.lockMonitor = lockMonitor
        self.preferences = preferences
    }

    func start() {
        controller.onModeChange = { [weak self] mode in self?.preferences.startMode = mode }
        lockMonitor.onLock = { [weak self] in self?.controller.screenLocked() }
        lockMonitor.onUnlock = { [weak self] in self?.controller.screenUnlocked() }
        lockMonitor.start()
    }

    func toggle() {
        controller.state == .off ? turnOn() : turnOff()
    }

    func setAutoOff(_ interval: AutoOffInterval) {
        controller.autoOff = interval
        preferences.autoOff = interval
    }

    private func turnOn() {
        controller.turnOn()

        // Sem isto, o App Nap coalesce os timers de um app de barra de menus em
        // segundo plano, e um ciclo de 30s pode virar minutos — tempo bastante
        // para o Teams amarelar antes do próximo tick.
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: .userInitiated,
            reason: "Presence mantendo o status disponível"
        )

        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.controller.tick()
                // O auto-off desliga por dentro; o runner acompanha.
                if self.controller.state == .off {
                    self.turnOff()
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(PresenceController.cycle * 1_000_000_000))
            }
        }
    }

    private func turnOff() {
        loop?.cancel()
        loop = nil
        controller.turnOff()
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
        }
        activityToken = nil
    }
}
