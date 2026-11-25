import AppKit
import Carbon
import HoltCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: AppModel
    @State private var dataStatusMessage: String?
    @State private var confirmResetStats = false
    @State private var showRulesEditor = false
    @State private var showFactSheet = false
    @State private var extensionStatus: String?

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
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Slang mix").font(.caption.weight(.medium))
                        Spacer()
                        Text(model.settings.slangMix < 0.34 ? "Archaic" : (model.settings.slangMix > 0.66 ? "Gen-Z" : "Balanced"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: $model.settings.slangMix, in: 0...1)
                    HStack {
                        Text("Archaic")
                        Spacer()
                        Text("Balanced")
                        Spacer()
                        Text("Gen-Z")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Toggle("Allow profanity in Holt's lines", isOn: $model.settings.allowProfanity)
                HStack {
                    Button(model.isQuietSnoozed ? "End quiet hour" : "Holt, quiet for 1 h") {
                        model.toggleSnoozeAllOneHour()
                    }
                    Button("What Holt knows…") {
                        showFactSheet = true
                    }
                }
            }

            Section("Notifications & schedules") {
                Toggle("Periodic check-in reminders", isOn: $model.settings.enableReminders)
                Picker("Reminder cadence", selection: $model.settings.reminderCadence) {
                    ForEach(ReminderCadence.allCases, id: \.self) { c in
                        Text(c.title).tag(c)
                    }
                }
                .disabled(!model.settings.enableReminders)
                Stepper(value: $model.settings.maxNudgesPerHour, in: 1...20) {
                    LabeledContent("Max nudges per hour", value: "\(model.settings.maxNudgesPerHour)")
                }
                Toggle("Quiet hours", isOn: $model.settings.quietHoursEnabled)
                if model.settings.quietHoursEnabled {
                    Stepper(value: $model.settings.quietStartHour, in: 0...23) {
                        LabeledContent("Quiet starts", value: String(format: "%02d:00", model.settings.quietStartHour))
                    }
                    Stepper(value: $model.settings.quietEndHour, in: 0...23) {
                        LabeledContent("Quiet ends", value: String(format: "%02d:00", model.settings.quietEndHour))
                    }
                }
                Toggle("Respect macOS Focus / Do Not Disturb", isOn: $model.settings.respectSystemFocus)
                Toggle("Morning brief", isOn: $model.settings.enableMorningBrief)
                if model.settings.enableMorningBrief {
                    Stepper(value: $model.settings.morningBriefHour, in: 4...12) {
                        LabeledContent("Morning brief hour", value: String(format: "%02d:00", model.settings.morningBriefHour))
                    }
                }
                Toggle("End-of-day summary", isOn: $model.settings.enableEODSummary)
                if model.settings.enableEODSummary {
                    Stepper(value: $model.settings.eodSummaryHour, in: 15...23) {
                        LabeledContent("Evening summary hour", value: String(format: "%02d:00", model.settings.eodSummaryHour))
                    }
                }
                Toggle("Weekly review (Sundays)", isOn: $model.settings.enableWeeklyReview)
            }

            Section("Auto-sessions") {
                Toggle("Start session when continuous work is detected", isOn: $model.settings.autoSessionDetectedWork)
                ForEach($model.settings.scheduledFocusBlocks) { $block in
                    HStack {
                        Toggle(block.label, isOn: $block.isEnabled)
                        Spacer()
                        Text(String(format: "%02d:%02d–%02d:%02d", block.startHour, block.startMinute, block.endHour, block.endMinute))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button {
                            model.settings.scheduledFocusBlocks.removeAll { $0.id == block.id }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                Button("Add weekday 10:00–12:00 focus block") {
                    model.settings.scheduledFocusBlocks.append(FocusBlockSchedule())
                }
                .font(.caption)
            }

            Section("Tracking & browsers") {
                Toggle("Track frontmost apps", isOn: $model.settings.trackApps)
                Toggle("Read window titles (needs Accessibility)", isOn: $model.settings.trackWindowTitles)
                    .disabled(!model.settings.trackApps)
                Toggle("Track browser tabs (Safari, Chromium, Firefox)", isOn: $model.settings.trackBrowsers)
                Toggle("Track YouTube video & category", isOn: $model.settings.trackYouTube)
                    .disabled(!model.settings.trackBrowsers)
                Picker("YouTube policy", selection: $model.settings.youtubePolicy) {
                    ForEach(YouTubePolicy.allCases, id: \.self) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .disabled(!model.settings.trackBrowsers || !model.settings.trackYouTube)

                Stepper(value: $model.settings.retentionDays, in: AppSettings.retentionRange, step: 30) {
                    LabeledContent("Keep raw history", value: "\(model.settings.retentionDays) days")
                }

                TextField("Chrome Extension ID (optional)", text: $model.settings.chromeExtensionId)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Install browser native host") { installNativeHost() }
                    Button("Category rules (\(model.userRules.count))…") { showRulesEditor = true }
                }
                if let extensionStatus {
                    Text(extensionStatus).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Toggle("On-device screen understanding (opt-in)", isOn: $model.settings.enableScreenUnderstanding)
                Stepper(value: $model.settings.screenIntervalMinutes, in: AppSettings.screenIntervalRange) {
                    LabeledContent("Check every", value: "\(model.settings.screenIntervalMinutes) min during work")
                }
                .disabled(!model.settings.enableScreenUnderstanding)

                HStack {
                    Text("Screen Recording permission")
                    Spacer()
                    Text(ScreenObserver.hasPermission() ? "Granted" : "Not granted")
                        .font(.caption)
                        .foregroundStyle(ScreenObserver.hasPermission() ? .green : .secondary)
                    if !ScreenObserver.hasPermission() {
                        Button("Request") {
                            _ = ScreenObserver.requestPermission()
                        }
                        .controlSize(.small)
                    }
                }

                TextField("Excluded apps/domains (comma-separated)", text: Binding(
                    get: { model.settings.screenExclusions.joined(separator: ", ") },
                    set: { raw in
                        model.settings.screenExclusions = raw
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                    }
                ))
                .textFieldStyle(.roundedBorder)
            } header: {
                Text("Screen understanding")
            } footer: {
                Text("Screenshots stay in memory for Apple Vision OCR and are discarded immediately. Password managers, banking, and private windows are excluded.")
            }

            Section("Data & backups") {
                HStack {
                    Button("Export JSON…") { exportJSON() }
                    Button("Export Tasks CSV…") { exportTasksCSV() }
                    Button("Export Sessions CSV…") { exportSessionsCSV() }
                }
                HStack {
                    Button("Import JSON…") { importJSON() }
                    Button("Backup now") { backupNow() }
                    Button("Show DB in Finder") { showInFinder() }
                }
                Button("Reset all stats…", role: .destructive) {
                    confirmResetStats = true
                }
                if let msg = dataStatusMessage {
                    Text(msg).font(.caption).foregroundStyle(.secondary)
                }
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
        .frame(width: 500)
        .frame(minHeight: 660, idealHeight: 820)
        .onChange(of: model.settings) { model.settingsChanged() }
        .onChange(of: model.launchAtLogin) { model.applyLaunchAtLogin() }
        .sheet(isPresented: $showRulesEditor) {
            RulesEditorSheet(model: model)
        }
        .sheet(isPresented: $showFactSheet) {
            FactSheetDebugSheet(model: model)
        }
        .confirmationDialog(
            "Reset all session & tracking stats?",
            isPresented: $confirmResetStats,
            titleVisibility: .visible
        ) {
            Button("Reset stats", role: .destructive) {
                try? DataPortability.resetAllStats(db: model.db)
                model.reloadTasksAndNotes()
                dataStatusMessage = "Stats reset."
            }
        } message: {
            Text("Tasks and notes stay intact, while sessions and tracking history are cleared.")
        }
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

    private func exportJSON() {
        guard let data = try? DataPortability.exportJSON(db: model.db) else { return }
        saveFile(defaultName: "holt-export.json", type: .json, data: data, label: "JSON exported.")
    }

    private func exportTasksCSV() {
        guard let csv = try? DataPortability.exportTasksCSV(db: model.db),
              let data = csv.data(using: .utf8) else { return }
        saveFile(defaultName: "holt-tasks.csv", type: .commaSeparatedText, data: data, label: "Tasks CSV exported.")
    }

    private func exportSessionsCSV() {
        guard let csv = try? DataPortability.exportSessionsCSV(db: model.db),
              let data = csv.data(using: .utf8) else { return }
        saveFile(defaultName: "holt-sessions.csv", type: .commaSeparatedText, data: data, label: "Sessions CSV exported.")
    }

    private func saveFile(defaultName: String, type: UTType, data: Data, label: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = defaultName
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                dataStatusMessage = label
            } catch {
                dataStatusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let data = try Data(contentsOf: url)
                try DataPortability.importJSON(data, into: model.db)
                model.reloadTasksAndNotes()
                dataStatusMessage = "Imported data."
            } catch {
                dataStatusMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private func backupNow() {
        do {
            let url = try DataPortability.performBackup(db: model.db, dayKey: HoltDay.key(for: .now), keepCount: 7)
            dataStatusMessage = "Saved backup \(url.lastPathComponent)."
        } catch {
            dataStatusMessage = "Backup failed: \(error.localizedDescription)"
        }
    }

    private func showInFinder() {
        if let path = model.db.path {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
    }

    private func installNativeHost() {
        do {
            let installed = try NativeMessagingInstaller.installAll(chromeExtensionId: model.settings.chromeExtensionId)
            extensionStatus = installed.isEmpty
                ? "No browser targets configured."
                : "Installed native messaging for: \(installed.joined(separator: ", "))."
        } catch {
            extensionStatus = "Failed: \(error.localizedDescription)"
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

private struct RulesEditorSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind: RuleKind = .domain
    @State private var pattern = ""
    @State private var category: ActivityCategory = .productive

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Category rules").font(.title3.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
            }

            HStack(spacing: 8) {
                Picker("", selection: $kind) {
                    ForEach(RuleKind.allCases, id: \.self) { k in
                        Text(k.title).tag(k)
                    }
                }
                .labelsHidden()
                .frame(width: 140)

                TextField("Pattern (e.g. youtube.com, com.apple.dt.Xcode)", text: $pattern)
                    .textFieldStyle(.roundedBorder)

                Picker("", selection: $category) {
                    ForEach(ActivityCategory.allCases, id: \.self) { c in
                        Text(c.title).tag(c)
                    }
                }
                .labelsHidden()
                .frame(width: 110)

                Button("Add") {
                    model.addCategoryRule(kind: kind, pattern: pattern, category: category)
                    pattern = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            List {
                ForEach(model.userRules) { rule in
                    HStack {
                        Text(RuleKind(rawValue: rule.kind)?.title ?? rule.kind)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        Text(rule.pattern).font(.callout)
                        Spacer()
                        Text(rule.category.capitalized)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(rule.category == "productive" ? .green : (rule.category == "distracting" ? .red : .secondary))
                        Button {
                            if let id = rule.id { model.deleteCategoryRule(id: id) }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .frame(minHeight: 240)
        }
        .padding(18)
        .frame(width: 580)
    }
}

private struct FactSheetDebugSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var jsonText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("What Holt knows (FactSheet)").font(.title3.weight(.semibold))
                Spacer()
                Button("Refresh") { load() }
                Button("Done") { dismiss() }
            }
            ScrollView {
                Text(jsonText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .frame(minHeight: 360)
        }
        .padding(18)
        .frame(width: 600)
        .onAppear { load() }
    }

    private func load() {
        guard let sheet = model.buildCurrentFactSheet() else {
            jsonText = "{}"
            return
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(sheet) {
            jsonText = String(decoding: data, as: UTF8.self)
        }
    }
}
