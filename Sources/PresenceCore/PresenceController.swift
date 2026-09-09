import Foundation

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

    private let declarer: ActivityDeclaring
    private let idleReader: IdleReading
    private let input: SyntheticInputting
    private let date: DateProviding
    private let sleeper: Sleeping
    private let initialMode: ActivityMode

    private var consecutiveHighIdle = 0
    private var startedAt: Date?

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
        startedAt = date.now
    }

    public func turnOff() {
        state = .off
        consecutiveHighIdle = 0
        startedAt = nil
    }

    public func tick() async {
        guard state == .active || state == .blocked else { return }

        var declareFailed = false
        do {
            try declarer.declare()
        } catch {
            declareFailed = true
        }

        if mode == .synthetic {
            guard input.isPermitted else {
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
            input.requestPermission()
            state = .blocked
        }
    }
}
