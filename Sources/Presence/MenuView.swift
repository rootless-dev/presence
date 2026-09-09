import PresenceCore
import SwiftUI

struct MenuView: View {

    @ObservedObject var controller: PresenceController
    let runner: PresenceRunner
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Button(controller.state == .off ? "Ativar" : "Desativar") {
            runner.toggle()
        }

        Text(statusText)

        if controller.state == .blocked {
            Button("Conceder permissão de Acessibilidade…") {
                SyntheticInput().openPermissionSettings()
            }
        }

        Divider()

        Picker("Desligar automaticamente após", selection: autoOffBinding) {
            ForEach(AutoOffInterval.allCases) { interval in
                Text(interval.label).tag(interval)
            }
        }

        Toggle("Abrir com o sistema", isOn: Binding(
            get: { launchAtLogin },
            set: { newValue in
                if LoginItem.setEnabled(newValue) {
                    launchAtLogin = newValue
                }
            }
        ))

        Divider()

        Button("Sair") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var autoOffBinding: Binding<AutoOffInterval> {
        Binding(
            get: { controller.autoOff },
            set: { runner.setAutoOff($0) }
        )
    }

    /// Mostra o contador de inatividade real. É a evidência visível de que o
    /// app está funcionando — sem isso o usuário só descobre que falhou quando
    /// alguém comenta que o status ficou amarelo.
    private var statusText: String {
        switch controller.state {
        case .off:
            return "Desligado"
        case .active where controller.mode == .synthetic:
            return String(format: "Ativo (modo estendido) · inatividade %.0fs", controller.lastIdle)
        case .active:
            return String(format: "Ativo · inatividade %.0fs", controller.lastIdle)
        case .blocked:
            return "Precisa de permissão de Acessibilidade"
        case .pausedLocked:
            return "Pausado (tela bloqueada)"
        }
    }
}
