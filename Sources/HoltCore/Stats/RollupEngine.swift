import Foundation
import GRDB

public struct DailyRollupRecord: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "daily_rollup"

    public var day: String
    public var focusSec: Int
    public var breakSec: Int
    public var idleSec: Int
    public var sessionsDone: Int
    public var sessionsAbandoned: Int
    public var tasksPlanned: Int
    public var tasksDone: Int
    public var tasksSkipped: Int
    public var distractSec: Int
    public var switches: Int
    public var focusScore: Int
    public var topApp: String?
    public var topSite: String?
    public var computedAt: Int64

    public enum CodingKeys: String, CodingKey {
        case day, switches
        case focusSec = "focus_sec"
        case breakSec = "break_sec"
        case idleSec = "idle_sec"
        case sessionsDone = "sessions_done"
        case sessionsAbandoned = "sessions_abandoned"
        case tasksPlanned = "tasks_planned"
        case tasksDone = "tasks_done"
        case tasksSkipped = "tasks_skipped"
        case distractSec = "distract_sec"
        case focusScore = "focus_score"
        case topApp = "top_app"
        case topSite = "top_site"
        case computedAt = "computed_at"
    }
}

public struct HourlyRollupRecord: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "hourly_rollup"

    public var day: String
    public var hour: Int
    public var focusSec: Int
    public var distractSec: Int

    public enum CodingKeys: String, CodingKey {
        case day, hour
        case focusSec = "focus_sec"
        case distractSec = "distract_sec"
    }
}

/// Computes and stores `daily_rollup` and `hourly_rollup` from raw tables.
public struct RollupEngine: Sendable {
    public static let scoreFormulaExplanation =
        "Focus score (0–100) = 60% focus vs. daily target (100 m) + 40% tasks done/planned − distraction share penalty (up to −40) − 8 per abandoned session."

    public let db: HoltDatabase

    public init(db: HoltDatabase) {
        self.db = db
    }

    @discardableResult
    public func recomputeDay(
        _ day: String,
        targetFocusSeconds: Int = 100 * 60,
        rolloverHour: Int = 4,
        calendar: Calendar = .current,
        now: Date = .now
    ) throws -> DailyRollupRecord {
        let bounds = HoltDay.bounds(forKey: day, rolloverHour: rolloverHour, calendar: calendar) ?? (0, Int64.max)
        let nowTs = Int64(now.timeIntervalSince1970)

        return try db.writer.write { db in
            let focusSec = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(active_sec), 0) FROM session WHERE kind = 'work' AND started_at >= ? AND started_at < ?",
                arguments: [bounds.start, bounds.end]
            ) ?? 0

            let breakSec = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(active_sec), 0) FROM session WHERE kind != 'work' AND started_at >= ? AND started_at < ?",
                arguments: [bounds.start, bounds.end]
            ) ?? 0

            let sessionsDone = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM session WHERE kind = 'work' AND end_reason = 'completed' AND started_at >= ? AND started_at < ?",
                arguments: [bounds.start, bounds.end]
            ) ?? 0

            let sessionsAbandoned = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM session WHERE kind = 'work' AND end_reason IN ('ended_early', 'converted_to_break', 'crashed') AND started_at >= ? AND started_at < ?",
                arguments: [bounds.start, bounds.end]
            ) ?? 0

            let idleSec = try Int.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(SUM(MAX(0, COALESCE(sp.ended_at, s.ended_at, ?) - sp.started_at)), 0)
                    FROM session_pause sp
                    JOIN session s ON s.id = sp.session_id
                    WHERE sp.reason IN ('idle', 'sleep', 'lock') AND sp.started_at >= ? AND sp.started_at < ?
                    """,
                arguments: [nowTs, bounds.start, bounds.end]
            ) ?? 0

            let tasksPlanned = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM task WHERE day = ?",
                arguments: [day]
            ) ?? 0

            let tasksDone = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM task WHERE day = ? AND status = 'done'",
                arguments: [day]
            ) ?? 0

            let tasksSkipped = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM task WHERE day = ? AND status = 'skipped'",
                arguments: [day]
            ) ?? 0

            let distractAppSec = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(MAX(0, ended_at - started_at)), 0) FROM app_span WHERE category = 'distracting' AND idle = 0 AND started_at >= ? AND started_at < ?",
                arguments: [bounds.start, bounds.end]
            ) ?? 0

            let distractWebSec = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(SUM(MAX(0, ended_at - started_at)), 0) FROM web_span WHERE category = 'distracting' AND started_at >= ? AND started_at < ?",
                arguments: [bounds.start, bounds.end]
            ) ?? 0

            let distractSec = max(distractAppSec, distractWebSec)

            let appRows = try Row.fetchAll(
                db,
                sql: "SELECT bundle_id, app_name, started_at, ended_at, category, session_kind FROM app_span WHERE idle = 0 AND started_at >= ? AND started_at < ? ORDER BY started_at ASC",
                arguments: [bounds.start, bounds.end]
            )

            var switches = 0
            var prevBundle: String?
            var hourlyFocus = Array(repeating: 0, count: 24)
            var hourlyDistract = Array(repeating: 0, count: 24)

            for row in appRows {
                let bundle: String = row["bundle_id"]
                let startTs: Int64 = row["started_at"]
                let endTs: Int64 = row["ended_at"]
                let cat: String? = row["category"]
                let skind: String? = row["session_kind"]
                if let prev = prevBundle, prev != bundle { switches += 1 }
                prevBundle = bundle

                let dur = Int(max(0, endTs - startTs))
                if dur > 0 {
                    let h = calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(startTs)))
                    if (0..<24).contains(h) {
                        if cat == "distracting" {
                            hourlyDistract[h] += dur
                        } else if skind == "work" || cat == "productive" {
                            hourlyFocus[h] += dur
                        }
                    }
                }
            }

            // Also attribute session focus seconds to hours if no app spans covered them
            let sessionRows = try Row.fetchAll(
                db,
                sql: "SELECT started_at, active_sec FROM session WHERE kind = 'work' AND started_at >= ? AND started_at < ?",
                arguments: [bounds.start, bounds.end]
            )
            if appRows.isEmpty {
                for row in sessionRows {
                    let startTs: Int64 = row["started_at"]
                    let active: Int = row["active_sec"]
                    let h = calendar.component(.hour, from: Date(timeIntervalSince1970: TimeInterval(startTs)))
                    if (0..<24).contains(h) {
                        hourlyFocus[h] += active
                    }
                }
            }

            let topApp = try String.fetchOne(
                db,
                sql: """
                    SELECT app_name FROM app_span
                    WHERE idle = 0 AND started_at >= ? AND started_at < ?
                    GROUP BY bundle_id
                    ORDER BY SUM(MAX(0, ended_at - started_at)) DESC
                    LIMIT 1
                    """,
                arguments: [bounds.start, bounds.end]
            )

            let topSite = try String.fetchOne(
                db,
                sql: """
                    SELECT domain FROM web_span
                    WHERE started_at >= ? AND started_at < ?
                    GROUP BY domain
                    ORDER BY SUM(MAX(0, ended_at - started_at)) DESC
                    LIMIT 1
                    """,
                arguments: [bounds.start, bounds.end]
            )

            let score = Self.computeFocusScore(
                focusSec: focusSec,
                targetFocusSec: targetFocusSeconds,
                tasksPlanned: tasksPlanned,
                tasksDone: tasksDone,
                distractSec: distractSec,
                sessionsDone: sessionsDone,
                sessionsAbandoned: sessionsAbandoned
            )

            let rollup = DailyRollupRecord(
                day: day,
                focusSec: focusSec,
                breakSec: breakSec,
                idleSec: idleSec,
                sessionsDone: sessionsDone,
                sessionsAbandoned: sessionsAbandoned,
                tasksPlanned: tasksPlanned,
                tasksDone: tasksDone,
                tasksSkipped: tasksSkipped,
                distractSec: distractSec,
                switches: switches,
                focusScore: score,
                topApp: topApp,
                topSite: topSite,
                computedAt: nowTs
            )
            try rollup.save(db)

            try db.execute(sql: "DELETE FROM hourly_rollup WHERE day = ?", arguments: [day])
            for h in 0..<24 where hourlyFocus[h] > 0 || hourlyDistract[h] > 0 {
                let hr = HourlyRollupRecord(
                    day: day,
                    hour: h,
                    focusSec: hourlyFocus[h],
                    distractSec: hourlyDistract[h]
                )
                try hr.save(db)
            }

            return rollup
        }
    }

    public static func computeFocusScore(
        focusSec: Int,
        targetFocusSec: Int,
        tasksPlanned: Int,
        tasksDone: Int,
        distractSec: Int,
        sessionsDone: Int,
        sessionsAbandoned: Int
    ) -> Int {
        if focusSec == 0 && tasksDone == 0 && sessionsAbandoned == 0 {
            return 0
        }
        let targetRatio = min(1.0, Double(focusSec) / Double(max(1, targetFocusSec)))
        let completionRatio: Double
        if tasksPlanned > 0 {
            completionRatio = min(1.0, Double(tasksDone) / Double(tasksPlanned))
        } else {
            completionRatio = sessionsDone > 0 ? 1.0 : 0.0
        }
        let base = 100.0 * (0.6 * targetRatio + 0.4 * completionRatio)
        let distractShare = Double(distractSec) / Double(max(1, focusSec + distractSec))
        let penalty = distractShare * 40.0 + Double(sessionsAbandoned) * 8.0
        return Int(max(0, min(100, (base - penalty).rounded())))
    }
}
