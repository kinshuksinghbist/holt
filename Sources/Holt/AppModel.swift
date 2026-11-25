import Foundation
import HoltCore
import Observation
import ServiceManagement

/// What the animation layer should show.
enum AnimationMode: Equatable {
    case idle, work, paused, rest
}

/// One line Holt said, for the feed.
struct HoltLine: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let text: String
}

/// App-wide state: owns the session engine, ticks the clock, reacts to the Mac going idle,
/// asleep or locked, and performs effects (lines, sounds, notifications).
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var state: SessionState
    private(set) var now: Date = .now
    private(set) var feed: [HoltLine] = []
    private(set) var today: DailyTally
    /// Length picked with the jelly or arrow keys for the next session, in minutes.
    private(set) var pendingMinutes: Int?
    /// Tone slider value: 0 polite · 0.5 punchy · 1 strict.
    var tone: Double
    var settings: AppSettings
    var launchAtLogin: Bool
    private(set) var loginItemMessage: String?

    @ObservationIgnored private let activity: ActivityMonitor
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var lineCounter = 0
    @ObservationIgnored private var awaySince: Date?

    private enum Keys {
        static let state = "holt.sessionState"
        static let tone = "holt.tone"
        static let settings = "holt.settings"
        static let today = "holt.today"
    }

    init() {
        let settings = Self.load(AppSettings.self, key: Keys.settings) ?? AppSettings()
        var state = Self.load(SessionState.self, key: Keys.state) ?? SessionState()
        state.updateConfig(settings.timerConfig)
        let todayKey = HoltDay.key(for: .now)
        let savedToday = Self.load(DailyTally.self, key: Keys.today)

        self.settings = settings
        self.state = state
        if let savedToday, savedToday.day == todayKey {
            self.today = savedToday
        } else {
            self.today = DailyTally(day: todayKey)
        }
        self.tone = UserDefaults.standard.object(forKey: Keys.tone) as? Double ?? 0.5
        let loginStatus = SMAppService.mainApp.status
        self.launchAtLogin = loginStatus == .enabled || loginStatus == .requiresApproval
        self.activity = ActivityMonitor()
        syncTicker()
    }

    /// Called once at launch: hooks up system events and catches up on anything that
    /// finished while Holt wasn't running.
    func startMonitoring() {
        activity.onAway = { [weak self] reason in self?.userWentAway(reason) }
        activity.onBack = { [weak self] in self?.userCameBack() }
        activity.onPoll = { [weak self] in self?.checkIdle() }
        activity.start()
        tick()
    }

    // MARK: - Derived values for the UI

    var toneBand: ToneBand { ToneBand(value: tone) }
    var lastLine: String? { feed.last?.text }
    var remaining: TimeInterval? { state.remaining(at: now) }
    var progress: Double { state.progress(at: now) }
    var isPausedSession: Bool { state.isPaused }

    /// Idle or a session waiting for Start: the jelly can set the next length.
    var canSetDuration: Bool {
        switch state.phase {
        case .idle, .ready: true
        case .running, .paused: false
        }
    }

    /// The kind of session the jelly / Start button would begin.
    var upcomingKind: SessionKind {
        if case let .ready(kind) = state.phase { return kind }
        return .work
    }

    /// Seconds shown on the jelly: the countdown, or the length the next session would have.
    var displayedSeconds: TimeInterval {
        if canSetDuration {
            return TimeInterval((pendingMinutes ?? settings.minutes(for: upcomingKind)) * 60)
        }
        return remaining ?? 0
    }

    var remainingFraction: Double { 1 - progress }

    var todaySummary: String {
        let sessions = today.sessionsCompleted == 1 ? "1 session" : "\(today.sessionsCompleted) sessions"
        return "Today · \(TimeFormat.duration(today.focusSeconds)) focused · \(sessions)"
    }

    var menuBarTitle: String {
        if case .idle = state.phase { return "" }
        return remaining.map(TimeFormat.clock) ?? ""
    }

    var menuBarSymbol: String {
        switch state.phase {
        case .idle: return "scope"
        case let .running(kind, _, _, _): return kind == .work ? "flame.fill" : "cup.and.saucer.fill"
        case .paused: return "pause.fill"
        case .ready: return "play.fill"
        }
    }

    var modeTitle: String {
        let cycle = "\(state.cyclePosition) of \(state.config.sessionsBeforeLongBreak)"
        switch state.phase {
        case .idle:
            return "Nothing going on"
        case let .running(kind, _, _, _):
            return Self.title(for: kind, cycle: cycle)
        case let .paused(kind, _, _, reason):
            return Self.title(for: kind, cycle: cycle) + " · " + Self.pauseText(reason)
        case let .ready(kind):
            return kind == .work ? "Next session ready" : "\(Self.title(for: kind, cycle: cycle)) ready"
        }
    }

    var sessionHint: String {
        switch state.phase {
        case .idle, .ready:
            return "Stretch the jelly to pick a length · ↩ starts"
        case .running(.work, _, _, _):
            return settings.pauseWhenIdle
                ? "Pauses itself after \(settings.idleMinutes) min away"
                : "Deep work in progress"
        case .running:
            return "The next session will be ready when this ends"
        case .paused:
            return "Paused time never counts as focus"
        }
    }

    var animationMode: AnimationMode {
        switch state.phase {
        case .idle, .ready: return .idle
        case let .running(kind, _, _, _): return kind == .work ? .work : .rest
        case .paused: return .paused
        }
    }

    private static func title(for kind: SessionKind, cycle: String) -> String {
        switch kind {
        case .work: "Deep work · \(cycle)"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }

    private static func pauseText(_ reason: PauseReason) -> String {
        switch reason {
        case .user: "paused"
        case .idle: "paused (idle)"
        case .sleep: "paused (Mac slept)"
        case .lock: "paused (screen locked)"
        }
    }

    // MARK: - Actions

    func perform(_ action: SessionAction) {
        let isStart = action == .startWork || action == .startNext
        let duration = isStart ? pendingMinutes.map { TimeInterval($0 * 60) } : nil
        apply { state, now in state.perform(action, now: now, duration: duration) }
        if isStart { pendingMinutes = nil }
    }

    /// Starts the upcoming session with an explicit length (jelly release).
    func start(minutes: Int) {
        guard canSetDuration else { return }
        pendingMinutes = minutes
        perform(state.phase == .idle ? .startWork : .startNext)
    }

    /// Starts the upcoming session with the pending or default length (jelly tap, ↩).
    func startUpcoming() {
        guard canSetDuration else { return }
        start(minutes: pendingMinutes ?? settings.minutes(for: upcomingKind))
    }

    func adjustPending(bySteps delta: Int) {
        guard canSetDuration else { return }
        let current = pendingMinutes ?? settings.minutes(for: upcomingKind)
        let shortest = JellyDial.minutes(atStep: 0)
        if current < shortest {
            // Breaks can be shorter than the dial's first step: ↑ goes to it, ↓ stays put.
            if delta > 0 { pendingMinutes = shortest }
            return
        }
        pendingMinutes = JellyDial.adjusted(current, bySteps: delta)
    }

    func handleNotificationAction(_ identifier: String) {
        guard let action = NotificationCategory.action(for: identifier) else { return }
        perform(action)
    }

    func saveTone() {
        UserDefaults.standard.set(tone, forKey: Keys.tone)
    }

    func settingsChanged() {
        let clamped = settings.clamped()
        if clamped != settings { settings = clamped }
        state.updateConfig(settings.timerConfig)
        Self.save(settings, key: Keys.settings)
        persist()
    }

    func applyLaunchAtLogin() {
        let service = SMAppService.mainApp
        let isOn = service.status == .enabled || service.status == .requiresApproval
        guard launchAtLogin != isOn else { return }
        do {
            if launchAtLogin {
                try service.register()
            } else {
                try service.unregister()
            }
            if service.status == .requiresApproval {
                loginItemMessage = "Approve Holt in System Settings → General → Login Items."
                SMAppService.openSystemSettingsLoginItems()
            } else {
                loginItemMessage = nil
            }
        } catch {
            loginItemMessage = "Couldn't change the login item: \(error.localizedDescription)"
            launchAtLogin = service.status == .enabled || service.status == .requiresApproval
        }
    }

    // MARK: - Transitions

    /// Applies a transition, records focus time, performs effects and persists.
    private func apply(_ transition: (inout SessionState, Date) -> [SessionEffect]) {
        now = .now
        rollDayIfNeeded()
        let before = state
        let workDone = state.workSecondsDone(at: now)
        let effects = transition(&state, now)
        // Some transitions change state without effects (End on a ready session): still save them.
        guard state != before else { return }
        // Old notification buttons would act on whatever session is current: clear them.
        Notifier.shared.clearDelivered()
        today.record(effects, workSecondsDone: workDone)
        handle(effects)
        persist()
        syncTicker()
    }

    private func tick() {
        apply { state, now in state.tick(now: now) }
    }

    private func handle(_ effects: [SessionEffect]) {
        for effect in effects {
            lineCounter += 1
            let line = Voice.line(for: effect, tone: toneBand, seed: lineCounter)
            if let line { say(line) }
            if case let .completed(kind) = effect {
                if settings.playSounds {
                    if kind == .work { Sounds.playWorkDone() } else { Sounds.playBreakOver() }
                }
                notifyCompletion(of: kind, line: line ?? "")
            }
        }
    }

    private func notifyCompletion(of kind: SessionKind, line: String) {
        guard settings.showNotifications else { return }
        if kind == .work {
            let breakRunning: Bool
            if case .running = state.phase { breakRunning = true } else { breakRunning = false }
            Notifier.shared.post(title: "Session complete", body: line,
                                 category: breakRunning ? .workDoneBreakRunning : .workDoneBreakReady)
        } else {
            Notifier.shared.post(title: "Break's over", body: line,
                                 category: state.phase == .ready(kind: .work) ? .breakOver : nil)
        }
    }

    private func say(_ text: String) {
        feed.append(HoltLine(date: .now, text: text))
        if feed.count > 50 { feed.removeFirst(feed.count - 50) }
    }

    // MARK: - Idle, sleep, lock

    private func checkIdle() {
        rollDayIfNeeded() // runs every 5 s, so "Today" turns over even with no session running
        guard settings.pauseWhenIdle else { return }
        let idle = activity.secondsSinceInput(keyboardCounts: settings.keyboardCountsAsActivity)
        let threshold = TimeInterval(settings.idleMinutes * 60)
        switch state.phase {
        case .running(.work, _, _, _) where idle >= threshold:
            // Retroactive: the idle minutes never count as focus.
            let since = Date.now.addingTimeInterval(-idle)
            apply { state, _ in state.autoPause(reason: .idle, since: since) }
        case .paused(_, _, _, .idle) where idle < 10: // polled every 5 s: don't miss a brief return
            apply { state, now in state.perform(.resume, now: now) }
        default:
            break
        }
    }

    private func userWentAway(_ reason: PauseReason) {
        if awaySince == nil { awaySince = .now }
        apply { state, now in state.autoPause(reason: reason, since: now) }
    }

    private func userCameBack() {
        tick() // a break may have ended while away
        guard let since = awaySince else { return }
        awaySince = nil
        guard case let .paused(_, _, _, reason) = state.phase, reason == .sleep || reason == .lock else { return }
        if Date.now.timeIntervalSince(since) < 60 {
            apply { state, now in state.perform(.resume, now: now) }
        } else if settings.showNotifications {
            Notifier.shared.post(title: "Session paused while you were away",
                                 body: "Resume when you're ready. The clock waited; so did the work.",
                                 category: .away)
        }
    }

    // MARK: - Clock

    /// Ticks only while a session is running, waking right after each displayed second flips.
    private func syncTicker() {
        let running: Bool
        if case .running = state.phase { running = true } else { running = false }
        if running, ticker == nil {
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    let delay = self?.delayToNextSecond() ?? 1
                    try? await Task.sleep(for: .seconds(delay))
                    guard let self, !Task.isCancelled else { return }
                    self.now = .now
                    self.tick()
                }
            }
        } else if !running {
            ticker?.cancel()
            ticker = nil
            now = .now
        }
    }

    private func delayToNextSecond() -> Double {
        guard let left = state.remaining(at: .now) else { return 1 }
        let fraction = left - left.rounded(.down)
        return fraction > 0.02 ? fraction + 0.01 : 1
    }

    private func rollDayIfNeeded() {
        let key = HoltDay.key(for: .now)
        if today.day != key { today = DailyTally(day: key) }
    }

    // MARK: - Persistence

    private func persist() {
        Self.save(state, key: Keys.state)
        Self.save(today, key: Keys.today)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
