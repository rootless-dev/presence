import XCTest
@testable import PresenceCore

final class ActivityDeclarerTests: XCTestCase {

    /// Declarar atividade não exige permissão nenhuma, então tem de funcionar
    /// sempre. Um erro aqui significa IOKit indisponível.
    func test_declare_naoLancaErro() {
        let declarer = ActivityDeclarer()
        XCTAssertNoThrow(try declarer.declare())
    }

    /// Chamadas repetidas reaproveitam a mesma assertion em vez de vazar uma
    /// nova a cada ciclo. O app chama isto a cada 30s, por horas.
    func test_declare_repetidoReaproveitaAssertion() throws {
        let declarer = ActivityDeclarer()
        try declarer.declare()
        let first = declarer.assertionIDForTesting
        XCTAssertNotEqual(first, 0, "a assertion tem de ter sido criada e guardada")
        try declarer.declare()
        XCTAssertEqual(declarer.assertionIDForTesting, first)
    }
}
