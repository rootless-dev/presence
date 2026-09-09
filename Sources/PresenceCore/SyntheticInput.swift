import AppKit
import ApplicationServices
import CoreGraphics

/// Injeta um evento de teclado inofensivo para zerar o contador de inatividade.
///
/// F15 (`kVK_F15`, 0x71) não existe em teclados Mac e nenhum app reage a ela.
public protocol SyntheticInputting {
    var isPermitted: Bool { get }
    func tap() -> Bool
    func requestPermission()
    func openPermissionSettings()
}

public struct SyntheticInput: SyntheticInputting {

    private let keyCode: CGKeyCode = 0x71

    public init() {}

    public var isPermitted: Bool {
        AXIsProcessTrusted()
    }

    /// Posta em `.cghidEventTap`, não em `.cgSessionEventTap`. Eventos
    /// injetados no tap de sessão podem não alcançar o IOHIDSystem e, portanto,
    /// não resetar o contador — o que tornaria este fallback inútil sem dar
    /// nenhum sinal de erro.
    public func tap() -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            return false
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// Mostra o diálogo do sistema pedindo Acessibilidade. Só aparece uma vez
    /// por processo; depois disso o usuário precisa ir aos Ajustes.
    public func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    public func openPermissionSettings() {
        let path = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        guard let url = URL(string: path) else { return }
        NSWorkspace.shared.open(url)
    }
}
