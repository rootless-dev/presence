import PresenceCore
import SwiftUI

@main
struct PresenceApp: App {

    @StateObject private var controller: PresenceController
    private let runner: PresenceRunner

    init() {
        let preferences = Preferences()
        let controller = PresenceController(
            declarer: ActivityDeclarer(),
            idleReader: IdleReader(),
            input: SyntheticInput(),
            date: SystemDate(),
            sleeper: SystemSleeper(),
            autoOff: preferences.autoOff,
            initialMode: preferences.startMode,
            lunchEnabled: preferences.lunchEnabled,
            lunchStart: preferences.lunchStart,
            lunchEnd: preferences.lunchEnd
        )
        _controller = StateObject(wrappedValue: controller)
        runner = PresenceRunner(
            controller: controller,
            lockMonitor: LockMonitor(),
            preferences: preferences
        )
        runner.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(controller: controller, runner: runner)
        } label: {
            Image(systemName: iconName)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            LunchSettingsView(controller: controller, runner: runner)
        }
    }

    private var iconName: String {
        switch controller.state {
        case .off: return "circle"
        case .blocked: return "circle.slash"
        case .pausedLocked: return "circle.dotted"
        case .pausedBreak: return "cup.and.saucer"
        case .active: return "circle.fill"
        }
    }
}
