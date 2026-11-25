import Foundation
import GRDB
import Testing
@testable import HoltCore

@Suite("Rollups & Stats performance")
struct StatsTests {
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    @Test func rollupComputesScoreAndHourlyBuckets() throws {
        let db = try HoltDatabase.openInMemory()
        let store = TaskStore(db: db)
        let spanStore = SpanStore(db: db)
        let rollupEngine = RollupEngine(db: db)

        let dayStart = utc.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 9, minute: 0))!
        let dayKey = HoltDay.key(for: dayStart, calendar: utc)

        let t1 = try store.createTask(title: "Ship M5", day: dayKey, now: dayStart)
        let t2 = try store.createTask(title: "Write docs", day: dayKey, now: dayStart)
        try store.setTaskStatus(taskId: t1.id!, status: .done, now: dayStart.addingTimeInterval(1500))
        try store.setTaskStatus(taskId: t2.id!, status: .done, now: dayStart.addingTimeInterval(3000))

        let s1 = try store.startSession(kind: .work, plannedSec: 1500, cycleIndex: 1, taskId: t1.id, now: dayStart)
        try store.finishSession(sessionId: s1, endReason: "completed", activeSec: 1500, at: dayStart.addingTimeInterval(1500))
        let s2 = try store.startSession(kind: .work, plannedSec: 1500, cycleIndex: 2, taskId: t2.id, now: dayStart.addingTimeInterval(1800))
        try store.finishSession(sessionId: s2, endReason: "completed", activeSec: 1500, at: dayStart.addingTimeInterval(3300))

        let ts0 = Int64(dayStart.timeIntervalSince1970)
        try spanStore.writeBatch(
            appSpans: [
                AppSpanRecord(bundleId: "com.apple.dt.Xcode", appName: "Xcode", startedAt: ts0, endedAt: ts0 + 1500, sessionId: s1, sessionKind: "work", category: "productive"),
                AppSpanRecord(bundleId: "com.hnc.Discord", appName: "Discord", startedAt: ts0 + 1500, endedAt: ts0 + 1800, sessionId: s1, sessionKind: "work", category: "distracting"),
                AppSpanRecord(bundleId: "com.apple.dt.Xcode", appName: "Xcode", startedAt: ts0 + 1800, endedAt: ts0 + 3300, sessionId: s2, sessionKind: "work", category: "productive"),
            ],
            webSpans: []
        )

        let daily = try rollupEngine.recomputeDay(dayKey, calendar: utc, now: dayStart.addingTimeInterval(4000))
        #expect(daily.focusSec == 3000)
        #expect(daily.sessionsDone == 2)
        #expect(daily.tasksDone == 2)
        #expect(daily.distractSec == 300)
        #expect(daily.switches == 2)
        #expect(daily.topApp == "Xcode")
        #expect(daily.focusScore > 50)

        let query = StatsQuery(db: db)
        let report = try query.report(fromDay: dayKey, toDay: dayKey, calendar: utc)
        #expect(report.totalFocusSeconds == 3000)
        #expect(report.mountainElevationMeters == 500) // 50 min * 10m
        #expect(report.hourlyBuckets[9].focusSeconds == 3000)
        #expect(report.switchEdges.count == 2)
    }

    @Test func oneYearSyntheticDatabaseRendersUnder150ms() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("holt-perf-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let db = try HoltDatabase.openOnDisk(at: dir.appendingPathComponent("perf.sqlite"))

        let base = utc.date(from: DateComponents(year: 2025, month: 11, day: 25, hour: 9))!
        var lastDay = "2025-11-25"

        try db.writer.write { db in
            for d in 0..<365 {
                let date = base.addingTimeInterval(Double(d) * 86400)
                let key = HoltDay.key(for: date, calendar: utc)
                lastDay = key
                let ts = Int64(date.timeIntervalSince1970)
                let rollup = DailyRollupRecord(
                    day: key,
                    focusSec: 5400,
                    breakSec: 900,
                    idleSec: 300,
                    sessionsDone: 3,
                    sessionsAbandoned: d % 5 == 0 ? 1 : 0,
                    tasksPlanned: 4,
                    tasksDone: 3,
                    tasksSkipped: 1,
                    distractSec: 600,
                    switches: 18,
                    focusScore: d % 7 == 0 ? 35 : 78,
                    topApp: "Xcode",
                    topSite: "github.com",
                    computedAt: ts
                )
                try rollup.save(db)
                for h in [9, 10, 14, 15] {
                    try HourlyRollupRecord(day: key, hour: h, focusSec: 1350, distractSec: 150).save(db)
                }
                // 20 raw spans per day = 7,300 raw app spans + 3,650 web spans
                for i in 0..<20 {
                    let sTs = ts + Int64(i * 300)
                    let isXcode = i % 3 != 0
                    var app = AppSpanRecord(
                        bundleId: isXcode ? "com.apple.dt.Xcode" : "com.google.Chrome",
                        appName: isXcode ? "Xcode" : "Google Chrome",
                        startedAt: sTs,
                        endedAt: sTs + 280,
                        sessionKind: "work",
                        category: isXcode ? "productive" : "neutral"
                    )
                    try app.insert(db)
                }
                for i in 0..<10 {
                    let wTs = ts + Int64(i * 400)
                    var web = WebSpanRecord(
                        browser: "Chrome",
                        domain: i % 4 == 0 ? "youtube.com" : "github.com",
                        startedAt: wTs,
                        endedAt: wTs + 200,
                        sessionKind: "work",
                        category: i % 4 == 0 ? "distracting" : "productive",
                        categorySource: "default"
                    )
                    try web.insert(db)
                }
            }
        }

        let query = StatsQuery(db: db)
        let start = CFAbsoluteTimeGetCurrent()
        let report = try query.report(fromDay: "2025-11-25", toDay: lastDay, calendar: utc)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        #expect(report.dailyRollups.count == 365)
        #expect(elapsedMs < 150.0, "Query took \(elapsedMs) ms")
    }
}
