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
}
