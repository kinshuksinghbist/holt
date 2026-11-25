import HoltCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Focus sessions") {
                minutesStepper("Work", value: $model.settings.workMinutes, range: AppSettings.workRange, step: 5)
                minutesStepper("Short break", value: $model.settings.shortBreakMinutes, range: AppSettings.shortBreakRange, step: 1)
                minutesStepper("Long break", value: $model.settings.longBreakMinutes, range: AppSettings.longBreakRange, step: 5)
                Stepper(value: $model.settings.sessionsBeforeLongBreak, in: AppSettings.cycleRange) {
                    LabeledContent("Long break after", value: "\(model.settings.sessionsBeforeLongBreak) sessions")
                }
                Toggle("Start breaks automatically", isOn: $model.settings.autoStartBreak)
                Toggle("Start the next session automatically", isOn: $model.settings.autoStartWork)
            }

            Section {
                Toggle("Pause when I'm away from the keyboard", isOn: $model.settings.pauseWhenIdle)
                Stepper(value: $model.settings.idleMinutes, in: AppSettings.idleRange) {
                    LabeledContent("After", value: "\(model.settings.idleMinutes) min without input")
                }
                .disabled(!model.settings.pauseWhenIdle)
                Toggle("Typing counts as activity", isOn: $model.settings.keyboardCountsAsActivity)
                    .disabled(!model.settings.pauseWhenIdle)
            } header: {
                Text("Focus guard")
            } footer: {
                Text("Sleep and screen lock always pause a work session. Idle, asleep and locked time never counts as focus.")
            }

            Section("Feedback") {
                Toggle("Sounds", isOn: $model.settings.playSounds)
                Toggle("Notifications", isOn: $model.settings.showNotifications)
                Toggle("Trackpad haptics on the jelly", isOn: $model.settings.jellyHaptics)
            }

            Section("Holt") {
                ToneSlider(model: model)
            }

            Section("General") {
                Toggle("Open Holt at login", isOn: $model.launchAtLogin)
                if let message = model.loginItemMessage {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
                LabeledContent("Version", value: Self.version)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 560, idealHeight: 720)
        .onChange(of: model.settings) { model.settingsChanged() }
        .onChange(of: model.launchAtLogin) { model.applyLaunchAtLogin() }
    }

    private func minutesStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        Stepper(value: value, in: range, step: step) {
            LabeledContent(title, value: "\(value.wrappedValue) min")
        }
    }

    private static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let short else { return "development build" }
        return build.map { "\(short) (\($0))" } ?? short
    }
}
