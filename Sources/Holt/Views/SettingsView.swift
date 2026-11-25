import AppKit
import Carbon
import HoltCore
import SwiftUI
import UniformTypeIdentifiers

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
                Toggle("Nudge when working too long", isOn: $model.settings.nudgeWorkingTooLong)
                Stepper(value: $model.settings.workingTooLongMinutes, in: AppSettings.workingTooLongRange, step: 15) {
                    LabeledContent("Working too long after", value: "\(model.settings.workingTooLongMinutes) min")
                }
                .disabled(!model.settings.nudgeWorkingTooLong)
            } header: {
                Text("Focus guard")
            } footer: {
                Text("Sleep and screen lock always pause a work session. Idle, asleep and locked time never counts as focus.")
            }

            Section("Sound & feedback") {
                Toggle("Sounds", isOn: $model.settings.playSounds)
                Picker("Completion sound", selection: $model.settings.soundChoice) {
                    ForEach(SoundChoice.allCases, id: \.self) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .disabled(!model.settings.playSounds)

                if model.settings.soundChoice == .custom {
                    HStack {
                        Text(model.settings.customSoundPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No file selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Choose…") { pickCustomSound() }
                    }
                    .disabled(!model.settings.playSounds)
                }

                HStack {
                    Text("Volume")
                    Slider(value: $model.settings.soundVolume, in: 0...1)
                    Button("Test") { Sounds.playWorkDone(settings: model.settings) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .disabled(!model.settings.playSounds)

                Toggle("Notifications", isOn: $model.settings.showNotifications)
                Toggle("Trackpad haptics on the jelly", isOn: $model.settings.jellyHaptics)
            }

            Section("Global hotkeys") {
                Toggle("Enable global shortcuts", isOn: $model.settings.hotkeysEnabled)
                HotkeyRow(title: "Start / Pause", shortcut: $model.settings.startPauseHotkey)
                    .disabled(!model.settings.hotkeysEnabled)
                HotkeyRow(title: "Take break", shortcut: $model.settings.breakHotkey)
                    .disabled(!model.settings.hotkeysEnabled)
                HotkeyRow(title: "End session", shortcut: $model.settings.endHotkey)
                    .disabled(!model.settings.hotkeysEnabled)
                Button("Reset shortcuts to defaults") {
                    model.settings.startPauseHotkey = .defaultStartPause
                    model.settings.breakHotkey = .defaultTakeBreak
                    model.settings.endHotkey = .defaultEndSession
                }
                .font(.caption)
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
        .frame(width: 480)
        .frame(minHeight: 620, idealHeight: 780)
        .onChange(of: model.settings) { model.settingsChanged() }
        .onChange(of: model.launchAtLogin) { model.applyLaunchAtLogin() }
    }

    private func minutesStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, step: Int) -> some View {
        Stepper(value: value, in: range, step: step) {
            LabeledContent(title, value: "\(value.wrappedValue) min")
        }
    }

    private func pickCustomSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            model.settings.customSoundPath = url.path
        }
    }

    private static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard let short else { return "development build" }
        return build.map { "\(short) (\($0))" } ?? short
    }
}

private struct HotkeyRow: View {
    let title: String
    @Binding var shortcut: HotkeyShortcut
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Toggle(title, isOn: $shortcut.isEnabled)
            Spacer()
            Button(isRecording ? "Press shortcut…" : shortcut.displayString) {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let keyCode = UInt32(event.keyCode)
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let handled = MainActor.assumeIsolated {
                if keyCode == 53 && flags.isEmpty { // Esc cancels
                    stopRecording()
                    return true
                }
                var carbonFlags: UInt32 = 0
                if flags.contains(.command) { carbonFlags |= HotkeyShortcut.cmdMask }
                if flags.contains(.option) { carbonFlags |= HotkeyShortcut.optionMask }
                if flags.contains(.control) { carbonFlags |= HotkeyShortcut.controlMask }
                if flags.contains(.shift) { carbonFlags |= HotkeyShortcut.shiftMask }
                guard carbonFlags != 0 else { return true }
                shortcut = HotkeyShortcut(keyCode: keyCode, modifiers: carbonFlags, isEnabled: shortcut.isEnabled)
                stopRecording()
                return true
            }
            return handled ? nil : event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
