import Foundation
import GRDB

public enum StatsRangePreset: String, Codable, Sendable, CaseIterable, Identifiable {
    case today, yesterday, thisWeek, lastWeek, thisMonth, custom

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This week"
        case .lastWeek: "Last week"
        case .thisMonth: "This month"
        case .custom: "Custom"
        }
    }
}

public enum HeatmapMetric: String, CaseIterable, Identifiable, Sendable {
    case focusMinutes, sessionsDone, tasksDone, focusScore, distractMinutes

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .focusMinutes: "Focus min"
        case .sessionsDone: "Sessions"
        case .tasksDone: "Tasks done"
        case .focusScore: "Focus score"
        case .distractMinutes: "Distraction min"
        }
    }
}

public struct HourBucket: Identifiable, Equatable, Sendable {
    public var id: Int { hour }
    public let hour: Int
    public let focusSeconds: Int
    public let distractSeconds: Int
}

public struct RibbonSegment: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case work, `break`, idle, distracted
    }
    public let id: Int
    public let startMinute: Double
    public let endMinute: Double
    public let kind: Kind
    public let label: String
}

public struct UsageBreakdownItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let totalSeconds: Int
    public let workSeconds: Int
    public let breakSeconds: Int
    public let category: String
}

public struct SwitchEdge: Identifiable, Equatable, Sendable {
    public var id: String { "\(fromApp)->\(toApp)" }
    public let fromApp: String
    public let toApp: String
    public let count: Int
}

public struct CreativeCards: Equatable, Sendable {
    public let bestFocusHour: String
    public let mostDangerousApp: String
    public let longestStreakDays: Int
    public let fastestDerailment: String
    public let topTimeSink: String
    public let avoidanceChampion: String
    public let comebackDay: String
}

public struct StatsReport: Equatable, Sendable {
    public let fromDay: String
    public let toDay: String
    public let dailyRollups: [DailyRollupRecord]
    public let hourlyBuckets: [HourBucket]
    public let ribbonSegments: [RibbonSegment]
    public let topApps: [UsageBreakdownItem]
    public let leastApps: [UsageBreakdownItem]
    public let topSites: [UsageBreakdownItem]
    public let switchEdges: [SwitchEdge]
    public let mostShiftedFrom: String
    public let mostShiftedTo: String
    public let totalFocusSeconds: Int
    public let totalBreakSeconds: Int
    public let totalDistractSeconds: Int
    public let youtubeEntertainmentSeconds: Int
    public let sessionsDone: Int
    public let sessionsAbandoned: Int
    public let tasksPlanned: Int
    public let tasksDone: Int
    public let tasksSkipped: Int
    public let averageFocusScore: Int
    public let mountainElevationMeters: Int
    public let everestProgress: Double
    public let cards: CreativeCards
    public let verdict: String
}

public struct StatsQuery: Sendable {
    public let db: HoltDatabase

    public init(db: HoltDatabase) {
        self.db = db
    }

    public static func dayBounds(
        preset: StatsRangePreset,
        customFrom: String? = nil,
        customTo: String? = nil,
        now: Date = .now,
        rolloverHour: Int = 4,
        calendar: Calendar = .current
    ) -> (from: String, to: String) {
        let todayKey = HoltDay.key(for: now, rolloverHour: rolloverHour, calendar: calendar)
        switch preset {
        case .today:
            return (todayKey, todayKey)
        case .yesterday:
            let y = HoltDay.addingDays(-1, toKey: todayKey, calendar: calendar) ?? todayKey
            return (y, y)
        case .thisWeek:
            let todayDate = HoltDay.date(fromKey: todayKey, calendar: calendar) ?? now
            let wd = calendar.component(.weekday, from: todayDate)
            let offset = -(wd - calendar.firstWeekday + 7) % 7
            let start = HoltDay.addingDays(offset, toKey: todayKey, calendar: calendar) ?? todayKey
            return (start, todayKey)
        case .lastWeek:
            let thisStart = dayBounds(preset: .thisWeek, now: now, rolloverHour: rolloverHour, calendar: calendar).from
            let start = HoltDay.addingDays(-7, toKey: thisStart, calendar: calendar) ?? thisStart
            let end = HoltDay.addingDays(-1, toKey: thisStart, calendar: calendar) ?? thisStart
            return (start, end)
        case .thisMonth:
            let prefix = String(todayKey.prefix(8))
            return ("\(prefix)01", todayKey)
        case .custom:
            let f = customFrom ?? todayKey
            let t = customTo ?? todayKey
            return f <= t ? (f, t) : (t, f)
        }
    }

    public func report(
        fromDay: String,
        toDay: String,
        tone: ToneBand = .punchy,
        rolloverHour: Int = 4,
        calendar: Calendar = .current
    ) throws -> StatsReport {
        let startTs = HoltDay.bounds(forKey: fromDay, rolloverHour: rolloverHour, calendar: calendar)?.start ?? 0
        let endTs = HoltDay.bounds(forKey: toDay, rolloverHour: rolloverHour, calendar: calendar)?.end ?? Int64.max

        return try db.writer.read { db in
            let rollups = try DailyRollupRecord.fetchAll(
                db,
                sql: "SELECT * FROM daily_rollup WHERE day >= ? AND day <= ? ORDER BY day ASC",
                arguments: [fromDay, toDay]
            )

            let hourlyRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT hour, COALESCE(SUM(focus_sec), 0) AS f, COALESCE(SUM(distract_sec), 0) AS d
                    FROM hourly_rollup
                    WHERE day >= ? AND day <= ?
                    GROUP BY hour
                    """,
                arguments: [fromDay, toDay]
            )
            var hourMap: [Int: (Int, Int)] = [:]
            for r in hourlyRows {
                let h: Int = r["hour"]
                hourMap[h] = (r["f"], r["d"])
            }
            let hourlyBuckets = (0..<24).map { h in
                HourBucket(hour: h, focusSeconds: hourMap[h]?.0 ?? 0, distractSeconds: hourMap[h]?.1 ?? 0)
            }

            // 24-h ribbon for `toDay`
            let ribbonBounds = HoltDay.bounds(forKey: toDay, rolloverHour: rolloverHour, calendar: calendar) ?? (startTs, endTs)
            let ribbonSpans = try AppSpanRecord.fetchAll(
                db,
                sql: "SELECT * FROM app_span WHERE started_at >= ? AND started_at < ? ORDER BY started_at ASC LIMIT 600",
                arguments: [ribbonBounds.start, ribbonBounds.end]
            )
            let ribbonSegments: [RibbonSegment] = ribbonSpans.enumerated().compactMap { idx, span in
                let sMin = Double(span.startedAt - ribbonBounds.start) / 60.0
                let eMin = Double(span.endedAt - ribbonBounds.start) / 60.0
                guard eMin > sMin else { return nil }
                let kind: RibbonSegment.Kind
                if span.idle != 0 {
                    kind = .idle
                } else if span.category == "distracting" {
                    kind = .distracted
                } else if span.sessionKind == "short_break" || span.sessionKind == "long_break" {
                    kind = .break
                } else {
                    kind = .work
                }
                return RibbonSegment(id: idx, startMinute: max(0, sMin), endMinute: min(1440, eMin), kind: kind, label: span.appName)
            }

            // Top / least apps via indexed GROUP BY
            let appRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT bundle_id,
                           MAX(app_name) AS name,
                           MAX(COALESCE(category, 'neutral')) AS cat,
                           COALESCE(SUM(MAX(0, ended_at - started_at)), 0) AS total_sec,
                           COALESCE(SUM(CASE WHEN session_kind = 'work' THEN MAX(0, ended_at - started_at) ELSE 0 END), 0) AS work_sec,
                           COALESCE(SUM(CASE WHEN session_kind IN ('short_break','long_break') THEN MAX(0, ended_at - started_at) ELSE 0 END), 0) AS break_sec
                    FROM app_span
                    WHERE idle = 0 AND started_at >= ? AND started_at < ?
                    GROUP BY bundle_id
                    ORDER BY total_sec DESC
                    """,
                arguments: [startTs, endTs]
            )
            let allApps = appRows.map { r in
                UsageBreakdownItem(
                    id: r["bundle_id"],
                    name: r["name"],
                    totalSeconds: r["total_sec"],
                    workSeconds: r["work_sec"],
                    breakSeconds: r["break_sec"],
                    category: r["cat"]
                )
            }
            let topApps = Array(allApps.prefix(10))
            let leastApps = Array(allApps.filter { $0.totalSeconds > 0 }.suffix(5).reversed())

            // Top sites via indexed GROUP BY
            let siteRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT domain,
                           MAX(COALESCE(category, 'neutral')) AS cat,
                           COALESCE(SUM(MAX(0, ended_at - started_at)), 0) AS total_sec,
                           COALESCE(SUM(CASE WHEN session_kind = 'work' THEN MAX(0, ended_at - started_at) ELSE 0 END), 0) AS work_sec,
                           COALESCE(SUM(CASE WHEN session_kind IN ('short_break','long_break') THEN MAX(0, ended_at - started_at) ELSE 0 END), 0) AS break_sec
                    FROM web_span
                    WHERE started_at >= ? AND started_at < ?
                    GROUP BY domain
                    ORDER BY total_sec DESC
                    LIMIT 12
                    """,
                arguments: [startTs, endTs]
            )
            let topSites = siteRows.map { r in
                let domain: String = r["domain"]
                return UsageBreakdownItem(
                    id: domain,
                    name: domain,
                    totalSeconds: r["total_sec"],
                    workSeconds: r["work_sec"],
                    breakSeconds: r["break_sec"],
                    category: r["cat"]
                )
            }

            let ytEntSec = try Int.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(SUM(MAX(0, ended_at - started_at)), 0)
                    FROM web_span
                    WHERE (domain LIKE '%youtube.com' OR domain = 'youtu.be')
                      AND category = 'distracting'
                      AND started_at >= ? AND started_at < ?
                    """,
                arguments: [startTs, endTs]
            ) ?? 0

            // Switch river (app -> app transitions using SQLite LAG window function)
            let switchRows = try Row.fetchAll(
                db,
                sql: """
                    WITH ordered AS (
                        SELECT app_name, LAG(app_name) OVER (ORDER BY started_at) AS prev_app
                        FROM app_span
                        WHERE idle = 0 AND started_at >= ? AND started_at < ?
                    )
                    SELECT prev_app, app_name, COUNT(*) AS cnt
                    FROM ordered
                    WHERE prev_app IS NOT NULL AND prev_app != app_name
                    GROUP BY prev_app, app_name
                    ORDER BY cnt DESC
                    LIMIT 12
                    """,
                arguments: [startTs, endTs]
            )
            let switchEdges = switchRows.map { r in
                SwitchEdge(fromApp: r["prev_app"], toApp: r["app_name"], count: r["cnt"])
            }
            var outCounts: [String: Int] = [:]
            var inCounts: [String: Int] = [:]
            for e in switchEdges {
                outCounts[e.fromApp, default: 0] += e.count
                inCounts[e.toApp, default: 0] += e.count
            }
            let mostShiftedFrom = outCounts.max(by: { $0.value < $1.value })?.key ?? "—"
            let mostShiftedTo = inCounts.max(by: { $0.value < $1.value })?.key ?? "—"

            // Totals from rollups (fast even for 365+ days)
            let totalFocus = rollups.reduce(0) { $0 + $1.focusSec }
            let totalBreak = rollups.reduce(0) { $0 + $1.breakSec }
            let totalDistract = rollups.reduce(0) { $0 + $1.distractSec }
            let sessionsDone = rollups.reduce(0) { $0 + $1.sessionsDone }
            let sessionsAbandoned = rollups.reduce(0) { $0 + $1.sessionsAbandoned }
            let tasksPlanned = rollups.reduce(0) { $0 + $1.tasksPlanned }
            let tasksDone = rollups.reduce(0) { $0 + $1.tasksDone }
            let tasksSkipped = rollups.reduce(0) { $0 + $1.tasksSkipped }
            let activeDays = rollups.filter { $0.focusSec > 0 || $0.tasksPlanned > 0 }
            let avgScore = activeDays.isEmpty ? 0 : activeDays.reduce(0) { $0 + $1.focusScore } / activeDays.count

            // Mountain log: 1 work minute = 10 m, Everest = 8849 m
            let elevation = (totalFocus / 60) * 10
            let everests = Double(elevation) / 8849.0

            // Creative cards
            let bestHourBucket = hourlyBuckets.max(by: { $0.focusSeconds < $1.focusSeconds })
            let bestHourStr = (bestHourBucket?.focusSeconds ?? 0) > 0
                ? String(format: "%02d:00", bestHourBucket!.hour)
                : "—"

            let dangerousApp = allApps.first(where: { $0.category == "distracting" && $0.workSeconds > 0 })?.name
                ?? allApps.first(where: { $0.category == "distracting" })?.name
                ?? "None"

            let topSink = (topSites.first(where: { $0.category == "distracting" })?.name)
                ?? (allApps.first(where: { $0.category == "distracting" })?.name)
                ?? "None"

            let avoidanceTitle = try String.fetchOne(
                db,
                sql: """
                    SELECT t.title FROM task_event te
                    JOIN task t ON t.id = te.task_id
                    WHERE te.kind = 'skipped' AND te.ts >= ? AND te.ts < ?
                    GROUP BY COALESCE(t.root_id, t.id)
                    ORDER BY COUNT(*) DESC
                    LIMIT 1
                    """,
                arguments: [startTs, endTs]
            ) ?? "None"

            let fastestDerailSec = try Int.fetchOne(
                db,
                sql: """
                    SELECT MIN(pe.ts - s.started_at)
                    FROM procrastination_event pe
                    JOIN session s ON s.id = pe.session_id
                    WHERE pe.ts >= ? AND pe.ts < ? AND pe.ts >= s.started_at
                    """,
                arguments: [startTs, endTs]
            )
            let fastestStr = fastestDerailSec.map { TimeFormat.clock(TimeInterval($0)) } ?? "—"

            let streak = Self.longestStreak(in: rollups)
            let comeback = Self.comebackDay(in: rollups)

            let cards = CreativeCards(
                bestFocusHour: bestHourStr,
                mostDangerousApp: dangerousApp,
                longestStreakDays: streak,
                fastestDerailment: fastestStr,
                topTimeSink: topSink,
                avoidanceChampion: avoidanceTitle,
                comebackDay: comeback
            )

            let verdict = Self.buildVerdict(
                focusSec: totalFocus,
                distractSec: totalDistract,
                sessionsDone: sessionsDone,
                tasksDone: tasksDone,
                tasksSkipped: tasksSkipped,
                avgScore: avgScore,
                tone: tone
            )

            return StatsReport(
                fromDay: fromDay,
                toDay: toDay,
                dailyRollups: rollups,
                hourlyBuckets: hourlyBuckets,
                ribbonSegments: ribbonSegments,
                topApps: topApps,
                leastApps: leastApps,
                topSites: topSites,
                switchEdges: switchEdges,
                mostShiftedFrom: mostShiftedFrom,
                mostShiftedTo: mostShiftedTo,
                totalFocusSeconds: totalFocus,
                totalBreakSeconds: totalBreak,
                totalDistractSeconds: totalDistract,
                youtubeEntertainmentSeconds: ytEntSec,
                sessionsDone: sessionsDone,
                sessionsAbandoned: sessionsAbandoned,
                tasksPlanned: tasksPlanned,
                tasksDone: tasksDone,
                tasksSkipped: tasksSkipped,
                averageFocusScore: avgScore,
                mountainElevationMeters: elevation,
                everestProgress: everests,
                cards: cards,
                verdict: verdict
            )
        }
    }

    private static func longestStreak(in rollups: [DailyRollupRecord]) -> Int {
        var best = 0
        var current = 0
        for r in rollups {
            if r.sessionsDone > 0 || r.focusSec >= 15 * 60 {
                current += 1
                best = max(best, current)
            } else {
                current = 0
            }
        }
        return best
    }

    private static func comebackDay(in rollups: [DailyRollupRecord]) -> String {
        guard rollups.count >= 2 else { return "—" }
        var bestJump = 0
        var bestDay = "—"
        for i in 1..<rollups.count {
            let prev = rollups[i - 1]
            let curr = rollups[i]
            if prev.focusScore <= 40 && curr.focusScore - prev.focusScore > bestJump {
                bestJump = curr.focusScore - prev.focusScore
                bestDay = curr.day
            }
        }
        return bestDay
    }

    private static func buildVerdict(
        focusSec: Int,
        distractSec: Int,
        sessionsDone: Int,
        tasksDone: Int,
        tasksSkipped: Int,
        avgScore: Int,
        tone: ToneBand
    ) -> String {
        let focusStr = TimeFormat.duration(TimeInterval(focusSec))
        let distractStr = TimeFormat.duration(TimeInterval(distractSec))
        if focusSec == 0 && tasksDone == 0 {
            switch tone {
            case .polite: return "No focus recorded in this range yet. Ready whenever you are."
            case .punchy: return "Zero focus logged. A pristine monument to potential."
            case .strict: return "Zero minutes of focus recorded. Unacceptable."
            }
        }
        switch tone {
        case .polite:
            return "\(focusStr) focused across \(sessionsDone) sessions (\(tasksDone) tasks done). Focus score: \(avgScore)/100."
        case .punchy:
            return "\(focusStr) of work, \(distractStr) of distractions, \(tasksSkipped) tasks dodged. Score: \(avgScore)/100."
        case .strict:
            return "Output: \(focusStr) (\(sessionsDone) sessions). Distractions: \(distractStr). Score: \(avgScore)/100."
        }
    }
}
