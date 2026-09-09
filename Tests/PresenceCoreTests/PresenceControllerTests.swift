import XCTest
@testable import PresenceCore

@MainActor
final class PresenceControllerTests: XCTestCase {

    /// Monta um controller com todas as dependências falsas. Cada teste ajusta
    /// o que precisa nos dublês antes de chamar `tick()`.
    private func makeController(
        idle: [TimeInterval] = [0],
        declarer: FakeDeclarer = FakeDeclarer(),
        input: FakeInput = FakeInput(),
        date: FakeDate = FakeDate(),
        autoOff: AutoOffInterval = .never,
        initialMode: ActivityMode = .declared
    ) -> PresenceController {
        PresenceController(
            declarer: declarer,
            idleReader: FakeIdleReader(values: idle),
            input: input,
            date: date,
            sleeper: NoSleep(),
            autoOff: autoOff,
            initialMode: initialMode
        )
    }

    func test_estadoInicial_ehDesligado() {
        let controller = makeController()
        XCTAssertEqual(controller.state, .off)
        XCTAssertEqual(controller.mode, .declared)
    }

    func test_estadoInicial_usaOModoInjetado() {
        let controller = makeController(initialMode: .synthetic)
        XCTAssertEqual(controller.mode, .synthetic)
    }

    func test_ligar_entraEmAtivoNoModoDeclarado() {
        let controller = makeController()
        controller.turnOn()
        XCTAssertEqual(controller.state, .active)
        XCTAssertEqual(controller.mode, .declared)
    }

    /// Numa máquina onde já se sabe que a declaração não basta, o app começa
    /// direto no modo que funciona em vez de gastar 3 ciclos redescobrindo.
    func test_ligar_respeitaOModoInicialInjetado() {
        let controller = makeController(initialMode: .synthetic)
        controller.turnOn()
        XCTAssertEqual(controller.mode, .synthetic)
    }

    func test_desligar_voltaParaDesligado() {
        let controller = makeController()
        controller.turnOn()
        controller.turnOff()
        XCTAssertEqual(controller.state, .off)
    }

    func test_tickDesligado_naoDeclaraAtividade() async {
        let declarer = FakeDeclarer()
        let controller = makeController(declarer: declarer)
        await controller.tick()
        XCTAssertEqual(declarer.callCount, 0)
    }

    func test_tickLigado_declaraAtividadeERegistraOIdle() async {
        let declarer = FakeDeclarer()
        let controller = makeController(idle: [2], declarer: declarer)
        controller.turnOn()
        await controller.tick()
        XCTAssertEqual(declarer.callCount, 1)
        XCTAssertEqual(controller.lastIdle, 2)
        XCTAssertEqual(controller.state, .active)
    }

    func test_idleAltoDuasVezes_naoEscala() async {
        let controller = makeController(idle: [10, 10])
        controller.turnOn()
        await controller.tick()
        await controller.tick()
        XCTAssertEqual(controller.mode, .declared)
    }

    func test_idleAltoTresVezes_escalaParaSintetico() async {
        let input = FakeInput()
        let controller = makeController(idle: [10, 10, 10], input: input)
        controller.turnOn()
        await controller.tick()
        await controller.tick()
        await controller.tick()
        XCTAssertEqual(controller.mode, .synthetic)
        XCTAssertEqual(controller.state, .active)
    }

    /// Uma leitura boa no meio significa que a declaração está funcionando —
    /// o contador de falhas volta a zero em vez de acumular pela sessão toda.
    func test_leituraBoaNoMeio_zeraOContadorDeFalhas() async {
        let controller = makeController(idle: [10, 10, 0, 10, 10])
        controller.turnOn()
        for _ in 0..<5 { await controller.tick() }
        XCTAssertEqual(controller.mode, .declared)
    }

    /// Erro do IOKit é sinal definitivo, não ruído: escala na hora.
    func test_falhaDaAssertion_escalaImediatamente() async {
        let declarer = FakeDeclarer()
        declarer.shouldThrow = true
        let controller = makeController(idle: [0], declarer: declarer)
        controller.turnOn()
        await controller.tick()
        XCTAssertEqual(controller.mode, .synthetic)
    }

    func test_escalarSemPermissao_vaiParaBloqueado() async {
        let input = FakeInput()
        input.isPermitted = false
        let controller = makeController(idle: [10, 10, 10], input: input)
        controller.turnOn()
        for _ in 0..<3 { await controller.tick() }
        XCTAssertEqual(controller.state, .blocked)
        XCTAssertEqual(input.requestCount, 1)
    }

    /// Conceder a permissão com o app aberto tem de passar a valer sozinho, sem
    /// exigir reinício.
    func test_permissaoConcedidaDepois_voltaParaAtivo() async {
        let input = FakeInput()
        input.isPermitted = false
        let controller = makeController(idle: [10, 10, 10, 10], input: input)
        controller.turnOn()
        for _ in 0..<3 { await controller.tick() }
        XCTAssertEqual(controller.state, .blocked)

        input.isPermitted = true
        await controller.tick()
        XCTAssertEqual(controller.state, .active)
        XCTAssertEqual(input.tapCount, 1)
    }

    /// A descoberta de que a declaração não basta tem de sair do controller,
    /// senão a próxima sessão a redescobre do zero.
    func test_escalar_notificaAMudancaDeModo() async {
        var notified: [ActivityMode] = []
        let controller = makeController(idle: [10, 10, 10])
        controller.onModeChange = { notified.append($0) }
        controller.turnOn()
        for _ in 0..<3 { await controller.tick() }
        XCTAssertEqual(notified, [.synthetic])
    }

    func test_modoSintetico_injetaTeclaACadaCiclo() async {
        let input = FakeInput()
        let controller = makeController(idle: [10, 10, 10, 0, 0], input: input)
        controller.turnOn()
        for _ in 0..<5 { await controller.tick() }
        XCTAssertEqual(controller.mode, .synthetic)
        XCTAssertEqual(input.tapCount, 2)
    }

    /// Cenário real: o app foi reinstalado, a assinatura ad-hoc mudou e o macOS
    /// revogou a Acessibilidade — mas as preferências dizem para começar em
    /// sintético. Sem pedir a permissão, o app ficaria mudo para sempre.
    func test_iniciarEmSinteticoSemPermissao_pedeAPermissaoUmaVez() async {
        let input = FakeInput()
        input.isPermitted = false
        let controller = makeController(idle: [0, 0, 0], input: input, initialMode: .synthetic)
        controller.turnOn()
        for _ in 0..<3 { await controller.tick() }
        XCTAssertEqual(controller.state, .blocked)
        XCTAssertEqual(input.requestCount, 1, "pede uma vez por sessão, não a cada ciclo")
    }

    /// Religar depois de desligar volta a pedir — o usuário pode ter concedido
    /// a permissão nesse meio-tempo e querer tentar de novo.
    func test_religar_voltaAPedirAPermissao() async {
        let input = FakeInput()
        input.isPermitted = false
        let controller = makeController(idle: [0, 0], input: input, initialMode: .synthetic)
        controller.turnOn()
        await controller.tick()
        controller.turnOff()
        controller.turnOn()
        await controller.tick()
        XCTAssertEqual(input.requestCount, 2)
    }
}
