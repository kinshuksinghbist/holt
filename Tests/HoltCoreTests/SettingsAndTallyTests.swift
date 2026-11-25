import Foundation
import Testing
@testable import HoltCore

@Suite("Settings")
struct AppSettingsTests {
    @Test func decodingEmptyObjectGivesDefaults() throws {
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(decoded == AppSettings())
    }

    @Test func missingKeysKeepTheirDefaults() throws {
        let json = #"{"workMinutes": 50, "pauseWhenIdle": false}"#
        let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        #expect(decoded.workMinutes == 50)
        #expect(decoded.pauseWhenIdle == false)
        #expect(decoded.shortBreakMinutes == 5)
        #expect(decoded.idleMinutes == 5)
    }

    @Test func roundTrips() throws {
        var s = AppSettings()
        s.workMinutes = 45
        s.jellyHaptics = false
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data) == s)
    }

    @Test func timerConfigUsesMinutes() {
        var s = AppSettings()
        s.workMinutes = 50
        s.sessionsBeforeLongBreak = 3
        s.autoStartWork = true
        let c = s.timerConfig
        #expect(c.workSeconds == 3000)
        #expect(c.shortBreakSeconds == 300)
        #expect(c.sessionsBeforeLongBreak == 3)
        #expect(c.autoStartWork)
        #expect(s.minutes(for: .longBreak) == 20)
    }

    @Test func clampingForcesRanges() {
        var s = AppSettings()
        s.workMinutes = 1
        s.longBreakMinutes = 999
        s.sessionsBeforeLongBreak = 0
        s.idleMinutes = 100
        s.workingTooLongMinutes = 5
        s.soundVolume = 4.5
        let c = s.clamped()
        #expect(c.workMinutes == 5)
        #expect(c.longBreakMinutes == 120)
        #expect(c.sessionsBeforeLongBreak == 2)
        #expect(c.idleMinutes == 30)
        #expect(c.workingTooLongMinutes == 30)
        #expect(c.soundVolume == 1.0)
    }

    @Test func hotkeyDisplayFormatting() {
        #expect(HotkeyShortcut.defaultStartPause.displayString == "⌃⌥Space")
        #expect(HotkeyShortcut.defaultTakeBreak.displayString == "⌃⌥B")
        #expect(HotkeyShortcut.defaultEndSession.displayString == "⌃⌥E")
    }
}

@Suite("Continuous work tracker")
struct ContinuousWorkTrackerTests {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func triggersAtThresholdAndSnoozes() {
        var tracker = ContinuousWorkTracker()
        let running = SessionPhase.running(kind: .work, startedAt: t0, deadline: t0.addingTimeInterval(7200), planned: 7200)
        let initial = tracker.update(phase: running, now: t0, thresholdMinutes: 90, enabled: true)
        #expect(!initial)
        var t = t0
        var triggered = false
        for _ in 0..<(95 * 60 / 5) {
            t = t.addingTimeInterval(5)
            if tracker.update(phase: running, now: t, thresholdMinutes: 90, enabled: true) {
                triggered = true
                break
            }
        }
        #expect(triggered)
        #expect(tracker.accumulatedSeconds >= 90.0 * 60.0)
        // Does not fire repeatedly without snooze expiry
        let repeatCheck = tracker.update(phase: running, now: t.addingTimeInterval(5), thresholdMinutes: 90, enabled: true)
        #expect(!repeatCheck)

        tracker.snooze(now: t, minutes: 20)
        let duringSnooze = tracker.update(phase: running, now: t.addingTimeInterval(10 * 60), thresholdMinutes: 90, enabled: true)
        #expect(!duringSnooze)
        let afterSnooze = tracker.update(phase: running, now: t.addingTimeInterval(20 * 60 + 5), thresholdMinutes: 90, enabled: true)
        #expect(afterSnooze)
    }

    @Test func breakOfOneMinuteResetsAccumulatedWork() {
        var tracker = ContinuousWorkTracker()
        let work = SessionPhase.running(kind: .work, startedAt: t0, deadline: t0.addingTimeInterval(1500), planned: 1500)
        _ = tracker.update(phase: work, now: t0, thresholdMinutes: 90, enabled: true)
        _ = tracker.update(phase: work, now: t0.addingTimeInterval(120), thresholdMinutes: 90, enabled: true)
        #expect(tracker.accumulatedSeconds == 120.0)

        let brk = SessionPhase.running(kind: .shortBreak, startedAt: t0, deadline: t0.addingTimeInterval(300), planned: 300)
        _ = tracker.update(phase: brk, now: t0.addingTimeInterval(125), thresholdMinutes: 90, enabled: true)
        _ = tracker.update(phase: brk, now: t0.addingTimeInterval(190), thresholdMinutes: 90, enabled: true)
        #expect(tracker.accumulatedSeconds == 0.0)
    }
}

@Suite("Daily tally")
struct DailyTallyTests {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func dayRollsOverAtFourAM() {
        #expect(HoltDay.key(for: date(25, 3, 59), calendar: utc) == "2026-11-24")
        #expect(HoltDay.key(for: date(25, 4, 0), calendar: utc) == "2026-11-25")
        #expect(HoltDay.key(for: date(25, 23, 30), calendar: utc) == "2026-11-25")
        #expect(HoltDay.key(for: date(25, 0, 30), rolloverHour: 0, calendar: utc) == "2026-11-25")
    }

    @Test func recordsCompletedAndAbandonedWork() {
        var tally = DailyTally(day: "2026-11-25")
        tally.record([.completed(.work), .started(.shortBreak)], workSecondsDone: 1500)
        tally.record([.endedEarly(.work), .started(.shortBreak)], workSecondsDone: 600)
        tally.record([.completed(.shortBreak), .endedEarly(.longBreak), .paused(.idle), .resumed], workSecondsDone: 999)
        #expect(tally.sessionsCompleted == 1)
        #expect(tally.sessionsEndedEarly == 1)
        #expect(tally.focusSeconds == 2100)
    }

    @Test func workSecondsDoneExcludesPauses() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var s = SessionState()
        s.perform(.startWork, now: t0)
        #expect(s.workSecondsDone(at: t0.addingTimeInterval(600)) == 600)
        s.perform(.pause, now: t0.addingTimeInterval(600))
        #expect(s.workSecondsDone(at: t0.addingTimeInterval(5000)) == 600)
        s.perform(.takeBreak, now: t0.addingTimeInterval(5000))
        #expect(s.workSecondsDone(at: t0.addingTimeInterval(5100)) == 0)
    }

    @Test func updatingConfigAffectsOnlyTheNextSession() {
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        var s = SessionState()
        s.perform(.startWork, now: t0)
        s.updateConfig(TimerConfig(workSeconds: 50 * 60))
        #expect(s.remaining(at: t0) == 25.0 * 60)
        s.perform(.endSession, now: t0)
        s.perform(.startWork, now: t0)
        #expect(s.remaining(at: t0) == 50.0 * 60)
    }

    @Test func compactDurations() {
        #expect(TimeFormat.duration(0) == "0m")
        #expect(TimeFormat.duration(25 * 60 + 59) == "25m")
        #expect(TimeFormat.duration(3600) == "1h")
        #expect(TimeFormat.duration(3900) == "1h 5m")
    }
}
