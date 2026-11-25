import AppKit
import ApplicationServices
import CoreGraphics
import HoltCore
import SwiftUI
import UserNotifications

struct OnboardingView: View {
    @Bindable var model: AppModel
    @State private var step: Int
    @State private var newTodoTitle = ""
    @State private var notificationsGranted = false
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var screenGranted = CGPreflightScreenCaptureAccess()
    @State private var extensionInstalled = NativeMessagingInstaller.isFirefoxInstalled()

    private let totalSteps = 7

    init(model: AppModel) {
        self.model = model
        _step = State(initialValue: min(max(model.settings.onboardingStep, 0), 6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to Holt")
                        .font(.title2.weight(.semibold))
                    Text("Step \(step + 1) of \(totalSteps)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Skip tour") {
                    model.completeOnboarding(startSession: false)
                }
                .buttonStyle(.borderless)
            }

            ProgressView(value: Double(step + 1), total: Double(totalSteps))

            Group {
                switch step {
                case 0: stepMeetHolt
                case 1: stepTimerAndJelly
                case 2: stepPermissions
                case 3: stepBrowsers
                case 4: stepListsAndTodos
                case 5: stepStartupAndAuto
                default: stepFirstSession
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack {
                if step > 0 {
                    Button("Back") { moveStep(to: step - 1) }
                        .buttonStyle(.bordered)
                }
                Spacer()
                if step < totalSteps - 1 {
                    Button("Next") { moveStep(to: step + 1) }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Start my first session") {
                        model.completeOnboarding(startSession: true)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(24)
        .frame(width: 620, height: 520)
        .task { await refreshPermissions() }
    }

    // MARK: - Steps

    private var stepMeetHolt: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("1. Meet Holt")
                .font(.headline)
            Text("Holt is your local-first accountability partner. Pick how sharp his commentary should be — everything runs locally on your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)

            ToneSlider(model: model)
                .padding(14)
                .holtGlass(cornerRadius: 14)

            HoltQuote(text: sampleLine(for: model.toneBand))
        }
    }

    private var stepTimerAndJelly: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("2. Stretch the Jelly Timer")
                .font(.headline)
            Text("Grab the jelly and pull outward to choose any duration (5–180 min). Use defaults below or adjust anytime in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 24) {
                JellyTimer(model: model, restRadius: 56)
                VStack(alignment: .leading, spacing: 10) {
                    Stepper(value: $model.settings.workMinutes, in: AppSettings.workRange, step: 5) {
                        LabeledContent("Work", value: "\(model.settings.workMinutes) min")
                    }
                    Stepper(value: $model.settings.shortBreakMinutes, in: AppSettings.shortBreakRange) {
                        LabeledContent("Short break", value: "\(model.settings.shortBreakMinutes) min")
                    }
                    Stepper(value: $model.settings.longBreakMinutes, in: AppSettings.longBreakRange, step: 5) {
                        LabeledContent("Long break", value: "\(model.settings.longBreakMinutes) min")
                    }
                }
            }
            .padding(12)
            .holtGlass(cornerRadius: 14)
        }
        .onChange(of: model.settings) { model.settingsChanged() }
    }

    private var stepPermissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("3. Permissions")
                .font(.headline)
            Text("Grant only what you want. Set Holt's macOS notification style to Alerts so action buttons stay visible.")
                .font(.callout)
                .foregroundStyle(.secondary)

            permissionRow(
                title: "Notifications (Required for nudges)",
                granted: notificationsGranted,
                buttonTitle: "Open Settings"
            ) {
                openSystemSettings("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
            }

            permissionRow(
                title: "Accessibility (Recommended for window titles)",
                granted: accessibilityGranted,
                buttonTitle: "Open Settings"
            ) {
                openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }

            permissionRow(
                title: "Automation (Safari & Chromium active tabs)",
                granted: true,
                statusText: "Per-browser prompt",
                buttonTitle: "Open Settings"
            ) {
                openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
            }

            permissionRow(
                title: "Screen Recording (Optional, on-device OCR)",
                granted: screenGranted,
                buttonTitle: screenGranted ? "Granted" : "Request"
            ) {
                _ = ScreenObserver.requestPermission()
                openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
            }

            Button("Refresh status") {
                Task { await refreshPermissions() }
            }
            .font(.caption)
        }
    }

    private var stepBrowsers: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("4. Browser Companion")
                .font(.headline)
            Text("Install Holt's native messaging host so the Firefox (required) and Chrome-family extensions can report YouTube categories and tab changes locally.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Label(
                    extensionInstalled ? "Firefox native host installed" : "Native host not installed yet",
                    systemImage: extensionInstalled ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                .foregroundStyle(extensionInstalled ? .green : .orange)
                Spacer()
                Button("Install native host") {
                    _ = try? NativeMessagingInstaller.installAll(chromeExtensionId: model.settings.chromeExtensionId)
                    extensionInstalled = NativeMessagingInstaller.isFirefoxInstalled()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .holtGlass(cornerRadius: 12)

            Text("Install the Holt Companion .xpi (Firefox) or unpacked Chrome extension from GitHub Releases, then click Install native host.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var stepListsAndTodos: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("5. Lists & Today's First Todos")
                .font(.headline)
            Text("Holt ships with Work, Personal, Health, Study, Admin, and Errands lists. Add what you're tackling today:")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                TextField("e.g. Finish project proposal", text: $newTodoTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addTodo() }
                Button("Add") { addTodo() }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.todayTasks.prefix(5)) { task in
                        Label(task.title, systemImage: "circle")
                            .font(.callout)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(10)
            .holtGlass(cornerRadius: 12)
        }
    }

    private var stepStartupAndAuto: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("6. Startup & Auto-Sessions")
                .font(.headline)
            Text("Holt lives in your menu bar. Choose whether he launches at login and whether he starts timers automatically when he spots continuous work.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Toggle("Open Holt at login", isOn: $model.launchAtLogin)
                .onChange(of: model.launchAtLogin) { model.applyLaunchAtLogin() }

            Toggle("Start session automatically after 2 min of detected productive work", isOn: $model.settings.autoSessionDetectedWork)
                .onChange(of: model.settings) { model.settingsChanged() }

            Toggle("Show helpful coach-marks on the menu bar & panel", isOn: $model.settings.showCoachMarks)
                .onChange(of: model.settings) { model.settingsChanged() }
        }
        .padding(14)
        .holtGlass(cornerRadius: 14)
    }

    private var stepFirstSession: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("7. Ready for Your First Session")
                .font(.headline)
            Text("Look for Holt's icon in the top-right menu bar next to the clock. You can also press ⌃⌥Space anywhere to start or pause.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("Menu bar icon opens the quick panel", systemImage: "scope")
                Label("Stretch the jelly to pick any session length", systemImage: "hand.draw")
                Label("Holt remembers tasks, skips, and distractions locally", systemImage: "lock.shield")
            }
            .font(.callout)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .holtGlass(cornerRadius: 14)
        }
    }

    // MARK: - Helpers

    private func permissionRow(
        title: String,
        granted: Bool,
        statusText: String? = nil,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(granted ? .green : .secondary)
            Text(title).font(.callout)
            Spacer()
            if let statusText {
                Text(statusText).font(.caption).foregroundStyle(.secondary)
            }
            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(8)
        .holtGlass(cornerRadius: 10)
    }

    private func moveStep(to next: Int) {
        step = min(max(next, 0), totalSteps - 1)
        model.settings.onboardingStep = step
        model.settingsChanged()
    }

    private func addTodo() {
        let trimmed = newTodoTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        model.quickAddTask(title: trimmed)
        newTodoTitle = ""
    }

    private func sampleLine(for band: ToneBand) -> String {
        switch band {
        case .polite: "Focus session started. One calm, steady block at a time."
        case .punchy: "Deep work engaged. Distractions will be documented."
        case .strict: "The timer has begun. Excuses have not been scheduled."
        }
    }

    private func openSystemSettings(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshPermissions() async {
        accessibilityGranted = AXIsProcessTrusted()
        screenGranted = CGPreflightScreenCaptureAccess()
        extensionInstalled = NativeMessagingInstaller.isFirefoxInstalled()
        notificationsGranted = await Self.checkNotificationPermission()
    }

    private nonisolated static func checkNotificationPermission() async -> Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }
}
