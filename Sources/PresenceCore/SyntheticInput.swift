import AppKit
import ApplicationServices
import CoreGraphics

/// Injects a harmless keyboard event to reset the idle counter.
///
/// F15 (`kVK_F15`, 0x71) doesn't exist on Mac keyboards and no app reacts to it.
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

    /// Posts to `.cghidEventTap`, not `.cgSessionEventTap`. Events injected
    /// into the session tap may not reach the IOHIDSystem and, therefore,
    /// may not reset the counter — which would make this fallback useless
    /// without giving any error signal.
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

    /// Shows the system dialog requesting Accessibility permission. It only
    /// appears once per process; after that the user needs to go to Settings.
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
