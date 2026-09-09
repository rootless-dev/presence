import XCTest
@testable import PresenceCore

final class IdleReaderTests: XCTestCase {

    /// A leitura tem de devolver um valor plausível: nunca negativo e nunca
    /// maior que um dia. Um valor fora disso significa que estamos lendo a
    /// chave errada ou convertendo a unidade errada.
    func test_idleSeconds_devolveValorPlausivel() {
        let reader = IdleReader()
        let value = reader.idleSeconds()
        XCTAssertGreaterThanOrEqual(value, 0)
        XCTAssertLessThan(value, 86_400)
    }

    /// Sem input, o contador cresce. Se houver atividade humana concorrente
    /// durante o teste, o valor cai — nesse caso o teste é ignorado em vez de
    /// falhar, porque o ruído não é um defeito do código.
    func test_idleSeconds_crescerSemInput() throws {
        let reader = IdleReader()
        let first = reader.idleSeconds()
        Thread.sleep(forTimeInterval: 2)
        let second = reader.idleSeconds()

        try XCTSkipIf(second < first, "houve input humano durante o teste")
        XCTAssertGreaterThan(second, first)
    }
}
