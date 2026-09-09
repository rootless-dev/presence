import XCTest
@testable import PresenceCore

final class PreferencesTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "presence.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func test_padrao_ehOitoHoras() {
        let prefs = Preferences(defaults: makeDefaults())
        XCTAssertEqual(prefs.autoOff, .hours8)
    }

    func test_gravaELeDeVolta() {
        let defaults = makeDefaults()
        Preferences(defaults: defaults).autoOff = .hour1
        XCTAssertEqual(Preferences(defaults: defaults).autoOff, .hour1)
    }

    /// Um valor corrompido no UserDefaults não pode derrubar o app.
    func test_valorInvalido_voltaAoPadrao() {
        let defaults = makeDefaults()
        defaults.set("banana", forKey: "autoOffInterval")
        XCTAssertEqual(Preferences(defaults: defaults).autoOff, .hours8)
    }

    /// Sem nada gravado, tenta o caminho barato e sem permissões primeiro.
    func test_modoInicial_padraoEhDeclared() {
        XCTAssertEqual(Preferences(defaults: makeDefaults()).startMode, .declared)
    }

    /// Uma vez descoberto que a declaração não basta nesta máquina, a próxima
    /// sessão já começa no modo que funciona.
    func test_modoInicial_gravaELeDeVolta() {
        let defaults = makeDefaults()
        Preferences(defaults: defaults).startMode = .synthetic
        XCTAssertEqual(Preferences(defaults: defaults).startMode, .synthetic)
    }
}
