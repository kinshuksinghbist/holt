import AppKit
import Foundation
import HoltCore
import Observation
import ServiceManagement
import SwiftUI

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

/// App-wide state: owns the session engine, SQLite database & task store, ticks the clock,
/// reacts to idle/sleep/lock, and performs effects (lines, sounds, notifications).
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let db: HoltDatabase
    let store: TaskStore

    private(set) var state: SessionState
    private(set) var now: Date = .now
    private(set) var feed: [HoltLine] = []
    private(set) var todaySummary: DayStatsSummary
    private(set) var lists: [TaskList] = []
    private(set) var todayTasks: [TaskItem] = []
    private(set) var chainMeta: [Int64: TaskChainMeta] = [:]
    private(set) var sessionNotes: [NoteRecord] = []
    var dayNote: String = ""
    var selectedTaskId: Int64?

    /// Set when a work session just finished so the UI can ask "What did you do?".
    var pendingSessionNoteId: Int64?
    /// Shown on first activity of a new Holt day when leftovers or recurring tasks await.
    var isPlanSheetPresented = false
    private(set) var planPreview = DayPlanPreview(leftovers: [], dueRecurring: [])

    /// Length picked with the jelly or arrow keys for the next session, in minutes.
    private(set) var pendingMinutes: Int?
    /// Tone slider value: 0 polite · 0.5 punchy · 1 strict.
    var tone: Double
    var settings: AppSettings
    var launchAtLogin: Bool
    private(set) var loginItemMessage: String?

    @ObservationIgnored var windowOpener: OpenWindowAction?
    @ObservationIgnored private let activity: ActivityMonitor
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var lineCounter = 0
    @ObservationIgnored private var awaySince: Date?
    @ObservationIgnored private var continuousWork = ContinuousWorkTracker()
    @ObservationIgnored private var activeSessionID: Int64?
    @ObservationIgnored private var currentDayKey: String

    private enum Keys {
        static let legacyState = "holt.sessionState"
        static let legacyTone = "holt.tone"
        static let legacySettings = "holt.settings"
        static let legacyToday = "holt.today"

        static let dbState = "session_state"
        static let dbSettings = "app_settings"
        static let dbTone = "tone"
        static let dbActiveSessionId = "active_session_id"
        static let dbLastPlannedDay = "last_planned_day"
        static let dbLastBackupDay = "last_backup_day"
    }

    init() {
        let openedDB: HoltDatabase
        do {
            let disk = try HoltDatabase.openOnDisk()
            if (try? disk.checkIntegrity()) == false {
                Diagnostics.log("Database integrity check returned false")
            }
            openedDB = disk
        } catch {
            Diagnostics.log("Failed to open on-disk DB (\(error)); falling back to in-memory")
            openedDB = try! HoltDatabase.openInMemory()
        }
        self.db = openedDB
        let store = TaskStore(db: openedDB)
        self.store = store

        // Migrate UserDefaults from M0/M1 on first launch with SQLite.
        let legacyState = UserDefaults.standard.data(forKey: Keys.legacyState)
        let legacySettings = UserDefaults.standard.data(forKey: Keys.legacySettings)
        let legacyToday = UserDefaults.standard.data(forKey: Keys.legacyToday)
        let legacyTone = UserDefaults.standard.object(forKey: Keys.legacyTone) as? Double
        try? store.migrateLegacyUserDefaults(
            stateData: legacyState,
            settingsData: legacySettings,
            todayData: legacyToday,
            tone: legacyTone
        )

        let settings = (try? store.loadSetting(AppSettings.self, key: Keys.dbSettings)) ?? AppSettings()
        var state = (try? store.loadSetting(SessionState.self, key: Keys.dbState)) ?? SessionState()
        state.updateConfig(settings.timerConfig)

        let todayKey = HoltDay.key(for: .now)
        self.currentDayKey = todayKey
        self.settings = settings
        self.state = state
        self.tone = (try? store.loadSetting(Double.self, key: Keys.dbTone)) ?? 0.5
        self.activeSessionID = try? store.loadSetting(Int64.self, key: Keys.dbActiveSessionId)
        if state.phase == .idle {
            try? store.closeCrashedSessions()
            self.activeSessionID = nil
        }

        self.todaySummary = (try? store.daySummary(day: todayKey)) ?? DayStatsSummary(
            day: todayKey, focusSeconds: 0, breakSeconds: 0, sessionsCompleted: 0,
            sessionsAbandoned: 0, tasksPlanned: 0, tasksDone: 0, tasksSkipped: 0
        )
        let loginStatus = SMAppService.mainApp.status
        self.launchAtLogin = loginStatus == .enabled || loginStatus == .requiresApproval
        self.activity = ActivityMonitor()

        reloadTasksAndNotes()
        if selectedTaskId == nil {
            selectedTaskId = todayTasks.first(where: { $0.taskStatus == .doing })?.id
                ?? todayTasks.first(where: { $0.taskStatus == .todo })?.id
        }
        checkNightlyBackupIfNeeded()
        checkPlanYourDayIfNeeded()
        syncTicker()
    }

    /// Called once at launch: hooks up system events, hotkeys, and catches up on anything that
    /// finished while Holt wasn't running.
    func startMonitoring() {
        activity.onAway = { [weak self] reason in self?.userWentAway(reason) }
        activity.onBack = { [weak self] in self?.userCameBack() }
        activity.onPoll = { [weak self] in self?.checkIdle() }
        activity.start()
        GlobalHotkeys.shared.configure(with: settings)
        tick()
    }

    // MARK: - Derived values for the UI

    var toneBand: ToneBand { ToneBand(value: tone) }
    var lastLine: String? { feed.last?.text }
    var remaining: TimeInterval? { state.remaining(at: now) }
    var progress: Double { state.progress(at: now) }
    var isPausedSession: Bool { state.isPaused }

    var undoneTodayTasks: [TaskItem] {
        todayTasks.filter { $0.taskStatus == .todo || $0.taskStatus == .doing }
    }

    var selectedTask: TaskItem? {
        if let id = selectedTaskId, let found = todayTasks.first(where: { $0.id == id }) {
            return found
        }
        return undoneTodayTasks.first
    }

    var canSetDuration: Bool {
        switch state.phase {
        case .idle, .ready: true
        case .running, .paused: false
        }
    }

    var upcomingKind: SessionKind {
        if case let .ready(kind) = state.phase { return kind }
        return .work
    }

    var displayedSeconds: TimeInterval {
        if canSetDuration {
            return TimeInterval((pendingMinutes ?? settings.minutes(for: upcomingKind)) * 60)
        }
        return remaining ?? 0
    }

    var remainingFraction: Double { 1 - progress }

    var todaySummaryText: String {
        let sessions = todaySummary.sessionsCompleted == 1 ? "1 session" : "\(todaySummary.sessionsCompleted) sessions"
        let left = todaySummary.tasksRemaining == 1 ? "1 todo" : "\(todaySummary.tasksRemaining) todos"
        return "Today · \(TimeFormat.duration(TimeInterval(todaySummary.focusSeconds))) · \(sessions) · \(left)"
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

    // MARK: - Session Actions

    func perform(_ action: SessionAction, startedBy: String = "user") {
        let isStart = action == .startWork || action == .startNext
        let duration = isStart ? pendingMinutes.map { TimeInterval($0 * 60) } : nil
        apply(startedBy: startedBy) { state, now in state.perform(action, now: now, duration: duration) }
        if isStart { pendingMinutes = nil }
    }

    func start(minutes: Int) {
        guard canSetDuration else { return }
        pendingMinutes = minutes
        perform(state.phase == .idle ? .startWork : .startNext)
    }

    func startUpcoming() {
        guard canSetDuration else { return }
        start(minutes: pendingMinutes ?? settings.minutes(for: upcomingKind))
    }

    func toggleStartPauseFromHotkey() {
        switch state.phase {
        case .idle, .ready:
            startUpcoming()
        case .running(.work, _, _, _):
            perform(.pause)
        case .running:
            perform(.endBreak)
        case .paused:
            perform(.resume)
        }
    }

    func adjustPending(bySteps delta: Int) {
        guard canSetDuration else { return }
        let current = pendingMinutes ?? settings.minutes(for: upcomingKind)
        let shortest = JellyDial.minutes(atStep: 0)
        if current < shortest {
            if delta > 0 { pendingMinutes = shortest }
            return
        }
        pendingMinutes = JellyDial.adjusted(current, bySteps: delta)
    }

    func openWindow(_ id: String) {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix(id) == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            windowOpener?.callAsFunction(id: id)
        }
        NSApp.activate()
    }

    func showMainWindow() {
        openWindow(WindowID.main)
    }

    func handleNotificationAction(_ identifier: String) {
        if identifier == NotificationCategory.snoozeTooLongID {
            continuousWork.snooze(now: .now, minutes: 20)
            say("Snoozed for 20 minutes. Do not make this a habit.")
            return
        }
        guard let action = NotificationCategory.action(for: identifier) else { return }
        perform(action, startedBy: "notification")
    }

    func handleQuickAddNotification(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        quickAddTask(title: trimmed)
        say("Added '\(trimmed)' to today's list.")
    }

    func saveTone() {
        try? store.saveSetting(tone, key: Keys.dbTone)
    }

    func settingsChanged() {
        let clamped = settings.clamped()
        if clamped != settings { settings = clamped }
        state.updateConfig(settings.timerConfig)
        GlobalHotkeys.shared.configure(with: settings)
        try? store.saveSetting(settings, key: Keys.dbSettings)
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

    // MARK: - Tasks, Lists, Notes, Plan Your Day

    func reloadTasksAndNotes() {
        lists = (try? store.fetchLists()) ?? []
        todayTasks = (try? store.fetchTasks(day: currentDayKey)) ?? []
        chainMeta = (try? store.chainMetadata(for: todayTasks)) ?? [:]
        dayNote = (try? store.fetchDayNote(day: currentDayKey)) ?? ""
        sessionNotes = (try? store.fetchSessionNotes(day: currentDayKey)) ?? []
        if let summary = try? store.daySummary(day: currentDayKey) {
            todaySummary = summary
        }
    }

    func quickAddTask(
        title: String,
        listId: Int64? = nil,
        priority: Int = 0,
        estimatePomos: Int? = nil,
        recurrence: TaskRecurrence = .none,
        link: String? = nil
    ) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let targetList = listId ?? lists.first?.id
        if let created = try? store.createTask(
            title: trimmed,
            listId: targetList,
            day: currentDayKey,
            priority: priority,
            estimatePomos: estimatePomos,
            link: link,
            recurrence: recurrence
        ) {
            if selectedTaskId == nil {
                selectedTaskId = created.id
            }
            reloadTasksAndNotes()
        }
    }

    func setTaskStatus(taskId: Int64, status: TaskStatus, skipReason: String? = nil) {
        try? store.setTaskStatus(taskId: taskId, status: status, skipReason: skipReason)
        if status.isTerminal && selectedTaskId == taskId {
            selectedTaskId = nil
        } else if status == .doing {
            selectedTaskId = taskId
        }
        reloadTasksAndNotes()
        if selectedTaskId == nil {
            selectedTaskId = undoneTodayTasks.first?.id
        }
    }

    func updateTask(_ task: TaskItem) {
        try? store.updateTask(task)
        reloadTasksAndNotes()
    }

    func deleteTask(id: Int64) {
        try? store.deleteTask(id: id)
        if selectedTaskId == id { selectedTaskId = nil }
        reloadTasksAndNotes()
    }

    func createList(name: String, color: String, icon: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = try? store.createList(name: trimmed, color: color, icon: icon)
        reloadTasksAndNotes()
    }

    func saveDayNote(_ text: String) {
        dayNote = text
        try? store.saveDayNote(day: currentDayKey, body: text)
    }

    func submitSessionNote(_ text: String) {
        guard let sessionId = pendingSessionNoteId else { return }
        try? store.addSessionNote(day: currentDayKey, sessionId: sessionId, body: text)
        pendingSessionNoteId = nil
        reloadTasksAndNotes()
    }

    func dismissSessionNotePrompt() {
        pendingSessionNoteId = nil
    }

    func openPlanYourDay() {
        planPreview = (try? store.planYourDayPreview(forDay: currentDayKey)) ?? DayPlanPreview(leftovers: [], dueRecurring: [])
        isPlanSheetPresented = true
    }

    func planKeepLeftover(_ task: TaskItem) {
        _ = try? store.keepLeftover(task, toDay: currentDayKey)
        refreshPlanPreviewAndTasks()
    }

    func planSkipLeftover(_ task: TaskItem, reason: String? = nil) {
        guard let id = task.id else { return }
        try? store.setTaskStatus(taskId: id, status: .skipped, skipReason: reason)
        refreshPlanPreviewAndTasks()
    }

    func planDropLeftover(_ task: TaskItem) {
        guard let id = task.id else { return }
        try? store.setTaskStatus(taskId: id, status: .abandoned)
        refreshPlanPreviewAndTasks()
    }

    func planFinishAndStartDay(keepRemaining: Bool) {
        if keepRemaining {
            try? store.rolloverUnfinishedTasks(toDay: currentDayKey)
        }
        try? store.instantiateRecurringTasks(forDay: currentDayKey)
        try? store.saveSetting(currentDayKey, key: Keys.dbLastPlannedDay)
        isPlanSheetPresented = false
        reloadTasksAndNotes()
    }

    private func refreshPlanPreviewAndTasks() {
        planPreview = (try? store.planYourDayPreview(forDay: currentDayKey)) ?? DayPlanPreview(leftovers: [], dueRecurring: [])
        reloadTasksAndNotes()
    }

    // MARK: - Transitions

    private func apply(startedBy: String = "user", _ transition: (inout SessionState, Date) -> [SessionEffect]) {
        now = .now
        rollDayIfNeeded()
        let before = state
        let workDone = state.workSecondsDone(at: now)
        let effects = transition(&state, now)
        guard state != before else { return }

        Notifier.shared.clearDelivered()
        recordSessionTransitions(before: before, effects: effects, workDone: workDone, startedBy: startedBy)
        handle(effects)
        checkContinuousWork()
        persist()
        reloadTasksAndNotes()
        syncTicker()
    }

    private func recordSessionTransitions(
        before: SessionState,
        effects: [SessionEffect],
        workDone: TimeInterval,
        startedBy: String
    ) {
        for effect in effects {
            switch effect {
            case .completed(let kind):
                if let sid = activeSessionID {
                    let active = kind == .work ? Int(workDone.rounded()) : Int((before.phase.kind.map { before.config.duration(of: $0) } ?? 0).rounded())
                    try? store.finishSession(sessionId: sid, endReason: "completed", activeSec: active, at: now)
                    if kind == .work { pendingSessionNoteId = sid }
                    activeSessionID = nil
                }
            case .endedEarly(let kind):
                if let sid = activeSessionID {
                    let reason = (state.phase.kind?.isBreak == true && kind == .work) ? "converted_to_break" : "ended_early"
                    let active = kind == .work ? Int(workDone.rounded()) : 0
                    try? store.finishSession(sessionId: sid, endReason: reason, activeSec: active, at: now)
                    if kind == .work && active >= 60 { pendingSessionNoteId = sid }
                    activeSessionID = nil
                }
            case .paused(let reason):
                if let sid = activeSessionID {
                    try? store.pauseSession(sessionId: sid, reason: reason, at: now)
                }
            case .resumed:
                if let sid = activeSessionID {
                    try? store.resumeSession(sessionId: sid, at: now)
                }
            case .started(let kind):
                if case let .running(_, _, _, planned) = state.phase {
                    let taskId = kind == .work ? selectedTask?.id : nil
                    activeSessionID = try? store.startSession(
                        kind: kind,
                        plannedSec: Int(planned.rounded()),
                        cycleIndex: state.cyclePosition,
                        taskId: taskId,
                        startedBy: startedBy,
                        now: now
                    )
                }
            case .extended:
                if activeSessionID == nil, case let .running(kind, startedAt, _, planned) = state.phase {
                    activeSessionID = try? store.startSession(
                        kind: kind,
                        plannedSec: Int(planned.rounded()),
                        cycleIndex: state.cyclePosition,
                        taskId: selectedTask?.id,
                        startedBy: "notification",
                        now: startedAt
                    )
                }
            }
        }
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
                if kind == .work {
                    Sounds.playWorkDone(settings: settings)
                } else {
                    Sounds.playBreakOver(settings: settings)
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

    // MARK: - Idle, sleep, lock, working too long

    private func checkIdle() {
        rollDayIfNeeded()
        checkContinuousWork()
        guard settings.pauseWhenIdle else { return }
        let idle = activity.secondsSinceInput(keyboardCounts: settings.keyboardCountsAsActivity)
        let threshold = TimeInterval(settings.idleMinutes * 60)
        switch state.phase {
        case .running(.work, _, _, _) where idle >= threshold:
            let since = Date.now.addingTimeInterval(-idle)
            apply { state, _ in state.autoPause(reason: .idle, since: since) }
        case .paused(_, _, _, .idle) where idle < 10:
            apply { state, now in state.perform(.resume, now: now) }
        default:
            break
        }
    }

    private func checkContinuousWork() {
        let shouldNudge = continuousWork.update(
            phase: state.phase,
            now: .now,
            thresholdMinutes: settings.workingTooLongMinutes,
            enabled: settings.nudgeWorkingTooLong
        )
        guard shouldNudge else { return }
        lineCounter += 1
        let line = Voice.workingTooLongLine(
            minutes: settings.workingTooLongMinutes,
            tone: toneBand,
            seed: lineCounter
        )
        say(line)
        if settings.showNotifications {
            Notifier.shared.post(title: "Working too long", body: line, category: .workingTooLong)
        }
    }

    private func userWentAway(_ reason: PauseReason) {
        if awaySince == nil { awaySince = .now }
        apply { state, now in state.autoPause(reason: reason, since: now) }
    }

    private func userCameBack() {
        tick()
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

    // MARK: - Clock & Day Rollover

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
        guard currentDayKey != key else { return }
        currentDayKey = key
        checkNightlyBackupIfNeeded()
        checkPlanYourDayIfNeeded()
        reloadTasksAndNotes()
    }

    private func checkPlanYourDayIfNeeded() {
        let lastPlanned = try? store.loadSetting(String.self, key: Keys.dbLastPlannedDay)
        guard lastPlanned != currentDayKey else { return }
        let preview = (try? store.planYourDayPreview(forDay: currentDayKey)) ?? DayPlanPreview(leftovers: [], dueRecurring: [])
        if !preview.isEmpty {
            planPreview = preview
            isPlanSheetPresented = true
        } else {
            try? store.saveSetting(currentDayKey, key: Keys.dbLastPlannedDay)
        }
    }

    private func checkNightlyBackupIfNeeded() {
        let lastBackup = try? store.loadSetting(String.self, key: Keys.dbLastBackupDay)
        guard lastBackup != currentDayKey else { return }
        if (try? DataPortability.performBackup(db: db, dayKey: currentDayKey, keepCount: 7)) != nil {
            try? store.saveSetting(currentDayKey, key: Keys.dbLastBackupDay)
        }
    }

    // MARK: - Persistence

    private func persist() {
        try? store.saveSetting(state, key: Keys.dbState)
        try? store.saveSetting(activeSessionID, key: Keys.dbActiveSessionId)
    }
}
