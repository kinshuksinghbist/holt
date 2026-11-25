import Foundation
import GRDB
import Testing
@testable import HoltCore

@Suite("TaskStore, rollover & migrations")
struct TaskStoreTests {
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func makeTempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("holt-test-\(UUID().uuidString)-\(name).sqlite")
    }

    @Test func migrationsCreateDefaultListsAndPassIntegrityCheck() throws {
        let db = try HoltDatabase.openInMemory()
        #expect(try db.checkIntegrity())
        let store = TaskStore(db: db)
        let lists = try store.fetchLists()
        #expect(lists.map(\.name) == ["Work", "Personal", "Health", "Study", "Admin", "Errands"])
    }

    @Test func diskDatabasePoolAndBackupsKeepAtMostSeven() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("holt-backup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let dbURL = dir.appendingPathComponent("holt.sqlite")
        let db = try HoltDatabase.openOnDisk(at: dbURL)
        let store = TaskStore(db: db)
        try store.createTask(title: "Write spec", day: "2026-11-20")

        let backupDir = dir.appendingPathComponent("Backups")
        for day in 1...9 {
            let key = String(format: "2026-11-%02d", day)
            try DataPortability.performBackup(db: db, toDirectory: backupDir, dayKey: key, keepCount: 7)
        }
        let files = try FileManager.default.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sqlite" }
        #expect(files.count == 7)
        #expect(!files.contains { $0.lastPathComponent == "holt-2026-11-01.sqlite" })
        #expect(files.contains { $0.lastPathComponent == "holt-2026-11-09.sqlite" })
    }

    @Test func rolloverChainsAndSkipCountsTrackAcrossDays() throws {
        let db = try HoltDatabase.openInMemory()
        let store = TaskStore(db: db)
        let lists = try store.fetchLists()
        let workId = lists.first!.id!

        let day1 = Date(timeIntervalSince1970: 1_800_000_000)
        let original = try store.createTask(title: "Finish proposal", listId: workId, day: "2026-11-20", priority: 2, now: day1)
        let rootId = original.id!
        #expect(original.rootId == rootId)

        // Skip on day 1? No, leave unfinished so it carries to day 2, then skip day 2 and re-create/carry.
        let day2 = day1.addingTimeInterval(86400)
        let carried1 = try store.rolloverUnfinishedTasks(toDay: "2026-11-21", now: day2)
        #expect(carried1.count == 1)
        #expect(carried1[0].carriedFromId == rootId)
        #expect(carried1[0].rootId == rootId)

        // Rollover again to day 3 (day 1 shouldn't duplicate because day 2 carried from it)
        let day3 = day2.addingTimeInterval(86400)
        let carried2 = try store.rolloverUnfinishedTasks(toDay: "2026-11-22", now: day3)
        #expect(carried2.count == 1)
        #expect(carried2[0].carriedFromId == carried1[0].id)
        #expect(carried2[0].rootId == rootId)

        #expect(try store.rolloverChainLength(forRootId: rootId) == 3)

        // Skip day 3 task, reopen, skip again
        try store.setTaskStatus(taskId: carried2[0].id!, status: .skipped, skipReason: "Too tired", now: day3)
        try store.setTaskStatus(taskId: carried2[0].id!, status: .todo, now: day3.addingTimeInterval(60))
        try store.setTaskStatus(taskId: carried2[0].id!, status: .skipped, skipReason: "Meetings", now: day3.addingTimeInterval(120))
        #expect(try store.skipCount(forRootId: rootId) == 2)

        // Focus time rolls up across the chain
        let s1 = try store.startSession(kind: .work, plannedSec: 1500, cycleIndex: 1, taskId: original.id, now: day1)
        try store.finishSession(sessionId: s1, endReason: "completed", activeSec: 1500, at: day1.addingTimeInterval(1500))
        let s2 = try store.startSession(kind: .work, plannedSec: 1500, cycleIndex: 2, taskId: carried2[0].id, now: day3)
        try store.finishSession(sessionId: s2, endReason: "ended_early", activeSec: 600, at: day3.addingTimeInterval(600))

        let meta = try store.chainMetadata(for: [carried2[0]])
        #expect(meta[rootId]?.daysCarried == 2)
        #expect(meta[rootId]?.skipCount == 2)
        #expect(meta[rootId]?.focusSeconds == 2100)
    }

    @Test func recurrenceRespectsDailyWeekdaysAndWeekly() throws {
        let db = try HoltDatabase.openInMemory()
        let store = TaskStore(db: db)

        // 2026-11-20 is a Friday
        let fri = utc.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 10))!
        let sat = utc.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 10))!
        let mon = utc.date(from: DateComponents(year: 2026, month: 11, day: 23, hour: 10))!
        let nextFri = utc.date(from: DateComponents(year: 2026, month: 11, day: 27, hour: 10))!

        let tDaily = try store.createTask(title: "Inbox zero", day: "2026-11-20", recurrence: .daily, now: fri)
        let tWeekday = try store.createTask(title: "Standup", day: "2026-11-20", recurrence: .weekdays, now: fri)
        let tWeekly = try store.createTask(title: "Weekly review", day: "2026-11-20", recurrence: .weekly, now: fri)

        // Mark Friday tasks done so they don't stay open
        try store.setTaskStatus(taskId: tDaily.id!, status: .done, now: fri)
        try store.setTaskStatus(taskId: tWeekday.id!, status: .done, now: fri)
        try store.setTaskStatus(taskId: tWeekly.id!, status: .done, now: fri)

        // Saturday: only daily is due
        let satTasks = try store.instantiateRecurringTasks(forDay: "2026-11-21", now: sat, calendar: utc)
        #expect(satTasks.map(\.title) == ["Inbox zero"])
        try store.setTaskStatus(taskId: satTasks[0].id!, status: .done, now: sat)

        // Monday: daily + weekdays
        let monTasks = try store.instantiateRecurringTasks(forDay: "2026-11-23", now: mon, calendar: utc)
        #expect(Set(monTasks.map(\.title)) == ["Inbox zero", "Standup"])
        for t in monTasks { try store.setTaskStatus(taskId: t.id!, status: .done, now: mon) }

        // Next Friday: all three
        let friTasks = try store.instantiateRecurringTasks(forDay: "2026-11-27", now: nextFri, calendar: utc)
        #expect(Set(friTasks.map(\.title)) == ["Inbox zero", "Standup", "Weekly review"])
    }

    @Test func exportImportRoundTripAndDeleteRange() throws {
        let db1 = try HoltDatabase.openInMemory()
        let store1 = TaskStore(db: db1)
        let t1 = try store1.createTask(title: "Task A", day: "2026-11-24")
        try store1.saveDayNote(day: "2026-11-24", body: "Scratchpad note")
        let sid = try store1.startSession(kind: .work, plannedSec: 1500, cycleIndex: 1, taskId: t1.id)
        try store1.finishSession(sessionId: sid, endReason: "completed", activeSec: 1500, at: .now)
        try store1.addSessionNote(day: "2026-11-24", sessionId: sid, body: "Shipped feature")

        let jsonData = try DataPortability.exportJSON(db: db1)
        let csv = try DataPortability.exportTasksCSV(db: db1)
        #expect(csv.contains("Task A"))

        let db2 = try HoltDatabase.openInMemory()
        try DataPortability.importJSON(jsonData, into: db2)
        let store2 = TaskStore(db: db2)
        #expect(try store2.fetchTasks(day: "2026-11-24").map(\.title) == ["Task A"])
        #expect(try store2.fetchDayNote(day: "2026-11-24") == "Scratchpad note")
        #expect(try store2.fetchSessionNotes(day: "2026-11-24").map(\.body) == ["Shipped feature"])

        try DataPortability.deleteHistory(db: db2, fromDay: "2026-11-24", toDay: "2026-11-24")
        #expect(try store2.fetchTasks(day: "2026-11-24").isEmpty)
        #expect(try store2.fetchDayNote(day: "2026-11-24").isEmpty)
    }

    @Test func legacyMigrationPreservesSettingsAndState() throws {
        let db = try HoltDatabase.openInMemory()
        let store = TaskStore(db: db)
        var s = AppSettings()
        s.workMinutes = 40
        let settingsData = try JSONEncoder().encode(s)
        var tally = DailyTally(day: "2026-11-25")
        tally.record([.completed(.work)], workSecondsDone: 2400)
        let tallyData = try JSONEncoder().encode(tally)

        try store.migrateLegacyUserDefaults(
            stateData: nil,
            settingsData: settingsData,
            todayData: tallyData,
            tone: 0.9
        )
        let loadedSettings = try store.loadSetting(AppSettings.self, key: "app_settings")
        #expect(loadedSettings?.workMinutes == 40)
        #expect(try store.loadSetting(Double.self, key: "tone") == 0.9)
        let summary = try store.daySummary(day: "2026-11-25")
        #expect(summary.focusSeconds == 2400)
        #expect(summary.sessionsCompleted == 1)
    }
}
