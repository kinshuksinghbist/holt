import Foundation
import GRDB

public struct FactSheet: Codable, Equatable, Sendable {
    public struct TodayFacts: Codable, Equatable, Sendable {
        public var day: String
        public var plannedCount: Int
        public var doneCount: Int
        public var doingTitle: String?
        public var topTodoTitle: String?
        public var leftCount: Int
        public var focusMinutes: Int
        public var distractMinutes: Int
        public var sessionsDone: Int
        public var sessionsAbandoned: Int
        public var focusScore: Int
        public var currentSessionKind: String?
        public var currentTaskTitle: String?
        public var currentApp: String?
        public var currentSite: String?
        public var currentVideoTitle: String?
        public var topDistraction: String?
    }

    public struct YesterdayFacts: Codable, Equatable, Sendable {
        public var day: String
        public var unfinishedCount: Int
        public var focusMinutes: Int
        public var averageFocusMinutes: Int
    }

    public struct RecentFacts: Codable, Equatable, Sendable {
        public var mostSkippedTitle: String?
        public var mostSkippedCount: Int
        public var longestRolloverTitle: String?
        public var longestRolloverDays: Int
        public var abandonedSessions7d: Int
        public var bestHour: String?
        public var worstHour: String?
        public var streakDays: Int
        public var weeklyFocusHours: Int
        public var weeklySessionsDone: Int
        public var weeklyTasksDone: Int
        public var weeklyTasksSkipped: Int
        public var weeklyAvgScore: Int
        public var weeklyDistractMinutes: Int
    }

    public var builtAt: Date
    public var today: TodayFacts
    public var yesterday: YesterdayFacts
    public var recent: RecentFacts
    public var recentTemplateIds: [String]
}

public enum FactSheetBuilder {
    public static func build(
        db: HoltDatabase,
        now: Date = .now,
        currentSessionKind: SessionKind? = nil,
        currentTaskTitle: String? = nil,
        currentApp: String? = nil,
        currentSite: String? = nil,
        currentVideoTitle: String? = nil,
        rolloverHour: Int = 4,
        calendar: Calendar = .current
    ) throws -> FactSheet {
        let todayKey = HoltDay.key(for: now, rolloverHour: rolloverHour, calendar: calendar)
        let yesterdayKey = HoltDay.addingDays(-1, toKey: todayKey, calendar: calendar) ?? todayKey
        let weekAgoKey = HoltDay.addingDays(-7, toKey: todayKey, calendar: calendar) ?? todayKey
        let monthAgoKey = HoltDay.addingDays(-30, toKey: todayKey, calendar: calendar) ?? todayKey

        let todayBounds = HoltDay.bounds(forKey: todayKey, rolloverHour: rolloverHour, calendar: calendar) ?? (0, Int64.max)
        let yesterdayBounds = HoltDay.bounds(forKey: yesterdayKey, rolloverHour: rolloverHour, calendar: calendar) ?? (0, 0)
        let sevenDaysAgoTs = Int64(now.addingTimeInterval(-7 * 86400).timeIntervalSince1970)
        let thirtyDaysAgoTs = Int64(now.addingTimeInterval(-30 * 86400).timeIntervalSince1970)

        return try db.writer.read { db in
            let plannedCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM task WHERE day = ?", arguments: [todayKey]) ?? 0
            let doneCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM task WHERE day = ? AND status = 'done'", arguments: [todayKey]) ?? 0
            let leftCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM task WHERE day = ? AND status IN ('todo','doing')", arguments: [todayKey]) ?? 0
            let doingTitle = try String.fetchOne(db, sql: "SELECT title FROM task WHERE day = ? AND status = 'doing' ORDER BY priority DESC LIMIT 1", arguments: [todayKey])
            let topTodoTitle = try String.fetchOne(db, sql: "SELECT title FROM task WHERE day = ? AND status = 'todo' ORDER BY priority DESC, created_at ASC LIMIT 1", arguments: [todayKey])

            let focusSec = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(active_sec), 0) FROM session WHERE kind = 'work' AND started_at >= ? AND started_at < ?",
                arguments: [todayBounds.start, todayBounds.end]
            ) ?? 0
            let sessionsDone = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM session WHERE kind = 'work' AND end_reason = 'completed' AND started_at >= ? AND started_at < ?",
                arguments: [todayBounds.start, todayBounds.end]
            ) ?? 0
            let sessionsAbandoned = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM session WHERE kind = 'work' AND end_reason IN ('ended_early','converted_to_break','crashed') AND started_at >= ? AND started_at < ?",
                arguments: [todayBounds.start, todayBounds.end]
            ) ?? 0
            let distractSec = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(MAX(0, ended_at - started_at)), 0) FROM web_span WHERE category = 'distracting' AND started_at >= ? AND started_at < ?",
                arguments: [todayBounds.start, todayBounds.end]
            ) ?? 0
            let topDistraction = try String.fetchOne(
                db,
                sql: "SELECT domain FROM web_span WHERE category = 'distracting' AND started_at >= ? AND started_at < ? GROUP BY domain ORDER BY SUM(MAX(0, ended_at - started_at)) DESC LIMIT 1",
                arguments: [todayBounds.start, todayBounds.end]
            )
            let todayScore = RollupEngine.computeFocusScore(
                focusSec: focusSec,
                targetFocusSec: 100 * 60,
                tasksPlanned: plannedCount,
                tasksDone: doneCount,
                distractSec: distractSec,
                sessionsDone: sessionsDone,
                sessionsAbandoned: sessionsAbandoned
            )

            // Yesterday
            let yUnfinished = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM task WHERE day = ? AND status IN ('todo','doing') AND id NOT IN (SELECT carried_from_id FROM task WHERE carried_from_id IS NOT NULL)",
                arguments: [yesterdayKey]
            ) ?? 0
            let yFocusSec = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(active_sec), 0) FROM session WHERE kind = 'work' AND started_at >= ? AND started_at < ?",
                arguments: [yesterdayBounds.start, yesterdayBounds.end]
            ) ?? 0
            let avgFocusSecDouble = try Double.fetchOne(
                db,
                sql: "SELECT COALESCE(AVG(focus_sec), 0) FROM daily_rollup WHERE day >= ? AND focus_sec > 0",
                arguments: [monthAgoKey]
            ) ?? 0.0
            let avgFocusSec = Int(avgFocusSecDouble.rounded())

            // Recent 7/30 days
            let skippedRow = try Row.fetchOne(
                db,
                sql: """
                    SELECT t.title, COUNT(*) AS cnt
                    FROM task_event te
                    JOIN task t ON t.id = te.task_id
                    WHERE te.kind = 'skipped' AND te.ts >= ?
                    GROUP BY COALESCE(t.root_id, t.id)
                    ORDER BY cnt DESC
                    LIMIT 1
                    """,
                arguments: [thirtyDaysAgoTs]
            )
            let mostSkippedTitle: String? = skippedRow?["title"]
            let mostSkippedCount: Int = skippedRow?["cnt"] ?? 0

            let rolloverRow = try Row.fetchOne(
                db,
                sql: """
                    SELECT MAX(title) AS title, COUNT(*) - 1 AS days
                    FROM task
                    WHERE day >= ?
                    GROUP BY COALESCE(root_id, id)
                    ORDER BY days DESC
                    LIMIT 1
                    """,
                arguments: [monthAgoKey]
            )
            let longestRolloverTitle: String? = rolloverRow?["title"]
            let longestRolloverDays: Int = max(0, rolloverRow?["days"] ?? 0)

            let abandoned7d = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM session WHERE kind = 'work' AND end_reason IN ('ended_early','converted_to_break','crashed') AND started_at >= ?",
                arguments: [sevenDaysAgoTs]
            ) ?? 0

            let bestHourInt = try Int.fetchOne(
                db,
                sql: "SELECT hour FROM hourly_rollup WHERE day >= ? GROUP BY hour ORDER BY SUM(focus_sec) DESC LIMIT 1",
                arguments: [monthAgoKey]
            )
            let worstHourInt = try Int.fetchOne(
                db,
                sql: "SELECT hour FROM hourly_rollup WHERE day >= ? GROUP BY hour ORDER BY SUM(distract_sec) DESC LIMIT 1",
                arguments: [monthAgoKey]
            )

            let recentDays = try DailyRollupRecord.fetchAll(
                db,
                sql: "SELECT * FROM daily_rollup WHERE day >= ? AND day <= ? ORDER BY day DESC",
                arguments: [monthAgoKey, todayKey]
            )
            var streak = 0
            for r in recentDays {
                if r.sessionsDone > 0 || r.focusSec >= 15 * 60 {
                    streak += 1
                } else if r.day != todayKey {
                    break
                }
            }

            let weekRollups = recentDays.filter { $0.day >= weekAgoKey }
            let weeklyFocusHours = weekRollups.reduce(0) { $0 + $1.focusSec } / 3600
            let weeklySessionsDone = weekRollups.reduce(0) { $0 + $1.sessionsDone }
            let weeklyTasksDone = weekRollups.reduce(0) { $0 + $1.tasksDone }
            let weeklyTasksSkipped = weekRollups.reduce(0) { $0 + $1.tasksSkipped }
            let weeklyDistractMin = weekRollups.reduce(0) { $0 + $1.distractSec } / 60
            let activeWeek = weekRollups.filter { $0.focusSec > 0 }
            let weeklyAvgScore = activeWeek.isEmpty ? todayScore : activeWeek.reduce(0) { $0 + $1.focusScore } / activeWeek.count

            let recentTemplates = try String.fetchAll(
                db,
                sql: "SELECT DISTINCT template_id FROM holt_message WHERE ts >= ?",
                arguments: [sevenDaysAgoTs]
            )

            return FactSheet(
                builtAt: now,
                today: FactSheet.TodayFacts(
                    day: todayKey,
                    plannedCount: plannedCount,
                    doneCount: doneCount,
                    doingTitle: doingTitle,
                    topTodoTitle: topTodoTitle,
                    leftCount: leftCount,
                    focusMinutes: focusSec / 60,
                    distractMinutes: distractSec / 60,
                    sessionsDone: sessionsDone,
                    sessionsAbandoned: sessionsAbandoned,
                    focusScore: todayScore,
                    currentSessionKind: currentSessionKind?.rawValue,
                    currentTaskTitle: currentTaskTitle ?? doingTitle ?? topTodoTitle,
                    currentApp: currentApp,
                    currentSite: currentSite,
                    currentVideoTitle: currentVideoTitle,
                    topDistraction: topDistraction
                ),
                yesterday: FactSheet.YesterdayFacts(
                    day: yesterdayKey,
                    unfinishedCount: yUnfinished,
                    focusMinutes: yFocusSec / 60,
                    averageFocusMinutes: avgFocusSec / 60
                ),
                recent: FactSheet.RecentFacts(
                    mostSkippedTitle: mostSkippedTitle,
                    mostSkippedCount: mostSkippedCount,
                    longestRolloverTitle: longestRolloverTitle,
                    longestRolloverDays: longestRolloverDays,
                    abandonedSessions7d: abandoned7d,
                    bestHour: bestHourInt.map { String(format: "%02d:00", $0) },
                    worstHour: worstHourInt.map { String(format: "%02d:00", $0) },
                    streakDays: streak,
                    weeklyFocusHours: weeklyFocusHours,
                    weeklySessionsDone: weeklySessionsDone,
                    weeklyTasksDone: weeklyTasksDone,
                    weeklyTasksSkipped: weeklyTasksSkipped,
                    weeklyAvgScore: weeklyAvgScore,
                    weeklyDistractMinutes: weeklyDistractMin
                ),
                recentTemplateIds: recentTemplates
            )
        }
    }
}
