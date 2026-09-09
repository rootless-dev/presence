import PresenceCore
import SwiftUI

/// The lunch break settings window.
///
/// A menu is the wrong place to pick a time of day: `MenuBarExtra` in `.menu`
/// style only renders lists, which forced a coarse set of preset hours. A
/// window gets real time fields and any minute of the day.
struct LunchSettingsView: View {

    @ObservedObject var controller: PresenceController
    let runner: PresenceRunner

    var body: some View {
        Form {
            Section {
                Toggle("Enable lunch break", isOn: Binding(
                    get: { controller.lunchEnabled },
                    set: { runner.setLunchEnabled($0) }
                ))

                Group {
                    DatePicker(
                        "From",
                        selection: time(controller.lunchStart, runner.setLunchStart),
                        displayedComponents: .hourAndMinute
                    )
                    DatePicker(
                        "To",
                        selection: time(controller.lunchEnd, runner.setLunchEnd),
                        displayedComponents: .hourAndMinute
                    )
                }
                .disabled(!controller.lunchEnabled)
            } footer: {
                Text(footerText)
                    .font(.callout)
                    .foregroundStyle(isWindowValid ? .secondary : Color.red)
                    .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize()
        .background(FrontmostWindow())
    }

    private var isWindowValid: Bool {
        controller.lunchStart < controller.lunchEnd
    }

    private var footerText: String {
        guard isWindowValid else {
            return "The end has to be after the start — the break is ignored until it is."
        }
        guard controller.lunchEnabled else {
            return "While disabled, the app keeps you available all day."
        }
        return "Every day in this window the app stops keeping you available, and resumes on its own when it ends."
    }

    /// Bridges a `TimeOfDay` to the `Date` a `DatePicker` works with. Only
    /// the hour and minute survive the round trip; the day is irrelevant.
    private func time(_ value: TimeOfDay, _ set: @escaping (TimeOfDay) -> Void) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: value.hour, minute: value.minute, second: 0, of: Date()
                ) ?? Date()
            },
            set: { newDate in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                set(TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0))
            }
        )
    }
}
