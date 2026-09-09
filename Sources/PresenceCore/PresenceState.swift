import Foundation

public enum PresenceState: Equatable {
    /// Toggle desligado. Nenhuma ação.
    case off
    /// Laço rodando.
    case active
    /// Precisa de input sintético, mas a permissão de Acessibilidade não foi concedida.
    case blocked
    /// Tela bloqueada. O toggle segue ligado, o laço está suspenso.
    case pausedLocked
}

public enum ActivityMode: Equatable {
    /// Power assertion do IOKit. Sem permissões.
    case declared
    /// Tecla F15 sintética. Exige Acessibilidade.
    case synthetic
}

public enum AutoOffInterval: String, CaseIterable, Identifiable {
    case never
    case hour1
    case hours4
    case hours8

    public var id: String { rawValue }

    public var seconds: TimeInterval? {
        switch self {
        case .never: return nil
        case .hour1: return 3600
        case .hours4: return 4 * 3600
        case .hours8: return 8 * 3600
        }
    }

    public var label: String {
        switch self {
        case .never: return "Nunca"
        case .hour1: return "1 hora"
        case .hours4: return "4 horas"
        case .hours8: return "8 horas"
        }
    }
}
