import PresenceCore
import SwiftUI

struct MenuView: View {

    @ObservedObject var controller: PresenceController
    let runner: PresenceRunner
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Button(controller.state == .off ? "Enable" : "Disable") {
            runner.toggle()
        }

        Text(statusText)

        if controller.state == .blocked {
            Button("Grant Accessibility permission…") {
                SyntheticInput().openPermissionSettings()
            }
        }

        if controller.state == .pausedBreak {
            Button("Resume now") {
                controller.resumeNow()
            }
        } else if controller.state != .off {
            Menu("Pause for") {
                ForEach(BreakDuration.allCases) { duration in
                    Button(duration.label) { controller.pause(for: duration) }
                }
            }
        }

        Divider()

        SettingsLink {
            Text("Lunch break…")
        }

        Picker("Turn off automatically after", selection: autoOffBinding) {
            ForEach(AutoOffInterval.allCases) { interval in
                Text(interval.label).tag(interval)
            }
        }

        Toggle("Launch at login", isOn: Binding(
            get: { launchAtLogin },
            set: { newValue in
                if LoginItem.setEnabled(newValue) {
                    launchAtLogin = newValue
                }
            }
        ))

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var autoOffBinding: Binding<AutoOffInterval> {
        Binding(
            get: { controller.autoOff },
            set: { runner.setAutoOff($0) }
        )
    }

    /// Shows the real idle counter. It's the visible evidence that the app
    /// is working — without it the user only finds out it failed after the
    /// machine already went idle.
    private var statusText: String {
        switch controller.state {
        case .off:
            return "Off"
        case .active where controller.mode == .synthetic:
            return String(format: "Active (extended mode) · idle %.0fs", controller.lastIdle)
        case .active:
            return String(format: "Active · idle %.0fs", controller.lastIdle)
        case .blocked:
            return "Accessibility permission required"
        case .pausedLocked:
            return "Paused (screen locked)"
        case .pausedBreak:
            guard let endsAt = controller.breakEndsAt else { return "Paused" }
            return "Paused · back at \(endsAt.formatted(date: .omitted, time: .shortened))"
        }
    }
}
