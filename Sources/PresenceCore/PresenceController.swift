import Foundation
import OSLog

/// Orquestra o laço que mantém o contador de inatividade baixo.
///
/// Toda dependência de sistema entra por protocolo, então o laço inteiro roda
/// nos testes sem tocar no IOKit e sem esperar tempo real.
@MainActor
public final class PresenceController: ObservableObject {

    /// Intervalo entre ciclos do laço.
    public static let cycle: TimeInterval = 30
    /// Espera entre declarar atividade e conferir o resultado.
    static let verifyDelay: TimeInterval = 1
    /// Acima disso, o contador é considerado alto demais.
    static let idleThreshold: TimeInterval = 5
    /// Leituras altas consecutivas antes de escalar para input sintético.
    static let failuresBeforeEscalation = 3

    @Published public private(set) var state: PresenceState = .off
    @Published public private(set) var mode: ActivityMode = .declared
    @Published public private(set) var lastIdle: TimeInterval = 0
    @Published public var autoOff: AutoOffInterval

    /// Avisa quando o modo muda, para que a camada de app persista a
    /// descoberta e a próxima sessão já comece no modo certo.
    public var onModeChange: ((ActivityMode) -> Void)?

    private let log = Logger(subsystem: "com.carlos.presence", category: "controller")

    private let declarer: ActivityDeclaring
    private let idleReader: IdleReading
    private let input: SyntheticInputting
    private let date: DateProviding
    private let sleeper: Sleeping
    private let initialMode: ActivityMode

    private var consecutiveHighIdle = 0
    private var startedAt: Date?
    private var hasRequestedPermission = false

    public init(
        declarer: ActivityDeclaring,
        idleReader: IdleReading,
        input: SyntheticInputting,
        date: DateProviding,
        sleeper: Sleeping,
        autoOff: AutoOffInterval,
        initialMode: ActivityMode = .declared
    ) {
        self.declarer = declarer
        self.idleReader = idleReader
        self.input = input
        self.date = date
        self.sleeper = sleeper
        self.autoOff = autoOff
        self.initialMode = initialMode
        self.mode = initialMode
    }

    public func turnOn() {
        state = .active
        mode = initialMode
        consecutiveHighIdle = 0
        hasRequestedPermission = false
        startedAt = date.now
        log.notice("ligado, modo declared, autoOff \(self.autoOff.rawValue, privacy: .public)")
    }

    public func turnOff() {
        state = .off
        consecutiveHighIdle = 0
        startedAt = nil
        log.notice("desligado")
    }

    public func tick() async {
        guard state == .active || state == .blocked else { return }

        if reachedAutoOff {
            turnOff()
            return
        }

        var declareFailed = false
        do {
            try declarer.declare()
        } catch {
            declareFailed = true
        }

        if mode == .synthetic {
            guard input.isPermitted else {
                requestPermissionOnce()
                state = .blocked
                return
            }
            state = .active
            _ = input.tap()
        }

        await sleeper.sleep(seconds: Self.verifyDelay)
        lastIdle = idleReader.idleSeconds()

        if declareFailed && mode == .declared {
            escalate()
            return
        }

        if lastIdle < Self.idleThreshold {
            consecutiveHighIdle = 0
        } else {
            consecutiveHighIdle += 1
            log.info("idle alto: \(self.lastIdle, format: .fixed(precision: 1)) s, falha \(self.consecutiveHighIdle)")
            if consecutiveHighIdle >= Self.failuresBeforeEscalation && mode == .declared {
                escalate()
            }
        }
    }

    /// Passa a injetar input de verdade. Se a permissão não estiver concedida,
    /// pede uma vez e assume `blocked` — o app não finge estar funcionando.
    private func escalate() {
        mode = .synthetic
        onModeChange?(.synthetic)
        consecutiveHighIdle = 0
        if input.isPermitted {
            state = .active
        } else {
            requestPermissionOnce()
            state = .blocked
        }
        log.notice("escalou para synthetic, estado \(String(describing: self.state), privacy: .public)")
    }

    /// O diálogo do sistema só aparece uma vez por processo; pedir a cada ciclo
    /// não traria o diálogo de volta e só geraria ruído.
    private func requestPermissionOnce() {
        guard !hasRequestedPermission else { return }
        hasRequestedPermission = true
        input.requestPermission()
    }

    /// Usa tempo de parede, não contagem de ciclos: se o Mac dormir três horas,
    /// essas três horas contam para o prazo.
    private var reachedAutoOff: Bool {
        guard let startedAt, let limit = autoOff.seconds else { return false }
        return date.now.timeIntervalSince(startedAt) > limit
    }

    /// A tela bloqueou. Declarar atividade agora reacenderia o display, e com a
    /// tela bloqueada o Teams marca ausente de qualquer forma — então o laço
    /// pausa. O toggle continua ligado.
    public func screenLocked() {
        guard state == .active || state == .blocked else { return }
        state = .pausedLocked
    }

    public func screenUnlocked() {
        guard state == .pausedLocked else { return }
        state = .active
    }
}
