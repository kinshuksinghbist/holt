import Foundation
import GRDB

public struct TaskChainMeta: Equatable, Sendable {
    public let daysCarried: Int
    public let skipCount: Int
    public let focusSeconds: Int

    public init(daysCarried: Int = 0, skipCount: Int = 0, focusSeconds: Int = 0) {
        self.daysCarried = daysCarried
        self.skipCount = skipCount
        self.focusSeconds = focusSeconds
    }
}

public struct RecurringTemplate: Equatable, Identifiable, Sendable {
    public let id: Int64
    public let rootId: Int64
    public let listId: Int64?
    public let title: String
    public let priority: Int
    public let estimatePomos: Int?
    public let link: String?
    public let recurrence: TaskRecurrence
}

public struct DayPlanPreview: Equatable, Sendable {
    public let leftovers: [TaskItem]
    public let dueRecurring: [RecurringTemplate]

    public var isEmpty: Bool { leftovers.isEmpty && dueRecurring.isEmpty }
}

public struct DayStatsSummary: Equatable, Sendable {
    public let day: String
    public let focusSeconds: Int
    public let breakSeconds: Int
    public let sessionsCompleted: Int
    public let sessionsAbandoned: Int
    public let tasksPlanned: Int
    public let tasksDone: Int
    public let tasksSkipped: Int

    public var tasksRemaining: Int {
        max(0, tasksPlanned - tasksDone - tasksSkipped)
    }
}

/// Repository for lists, tasks, rollover chains, notes, sessions, pauses, and settings.
public struct TaskStore: Sendable {
    public let db: HoltDatabase

    public init(db: HoltDatabase) {
        self.db = db
    }

    // MARK: - Settings KV

    public func saveSetting<T: Encodable>(_ value: T, key: String) throws {
        let data = try JSONEncoder().encode(value)
        let json = String(decoding: data, as: UTF8.self)
        try db.writer.write { db in
            try SettingRecord(key: key, value: json).save(db)
        }
    }

    public func loadSetting<T: Decodable>(_ type: T.Type, key: String) throws -> T? {
        try db.writer.read { db in
            guard let row = try SettingRecord.fetchOne(db, key: key),
                  let data = row.value.data(using: .utf8) else {
                return nil
            }
            return try JSONDecoder().decode(type, from: data)
        }
    }

    public func hasSetting(key: String) throws -> Bool {
        try db.writer.read { db in
            try SettingRecord.fetchOne(db, key: key) != nil
        }
    }

    // MARK: - Legacy UserDefaults Migration

    public func migrateLegacyUserDefaults(
        stateData: Data?,
        settingsData: Data?,
        todayData: Data?,
        tone: Double?,
        now: Date = .now
    ) throws {
        guard try !hasSetting(key: "legacy_migrated") else { return }
        if let settingsData, let decoded = try? JSONDecoder().decode(AppSettings.self, from: settingsData) {
            try saveSetting(decoded, key: "app_settings")
        }
        if let stateData, let decoded = try? JSONDecoder().decode(SessionState.self, from: stateData) {
            try saveSetting(decoded, key: "session_state")
        }
        if let tone {
            try saveSetting(tone, key: "tone")
        }
        if let todayData, let tally = try? JSONDecoder().decode(DailyTally.self, from: todayData) {
            let existingCount = try db.writer.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM session") ?? 0
            }
            if existingCount == 0 && (tally.focusSeconds > 0 || tally.sessionsCompleted > 0) {
                let bounds = HoltDay.bounds(forKey: tally.day)
                let start = bounds?.start ?? Int64(now.timeIntervalSince1970)
                let active = Int(tally.focusSeconds.rounded())
                let count = max(1, tally.sessionsCompleted)
                let perSession = count > 0 ? active / count : active
                try db.writer.write { db in
                    for i in 0..<count {
                        let ts = start + Int64(i * max(60, perSession))
                        var rec = SessionRecord(
                            kind: SessionKind.work.dbKind,
                            plannedSec: max(perSession, 1500),
                            cycleIndex: i + 1,
                            taskId: nil,
                            startedAt: ts,
                            endedAt: ts + Int64(perSession),
                            endReason: tally.sessionsCompleted > i ? "completed" : "ended_early",
                            activeSec: perSession,
                            startedBy: "user"
                        )
                        try rec.insert(db)
                    }
                }
            }
        }
        try saveSetting(true, key: "legacy_migrated")
    }

    // MARK: - Lists

    public func fetchLists(includeArchived: Bool = false) throws -> [TaskList] {
        try db.writer.read { db in
            let sql = includeArchived
                ? "SELECT * FROM list ORDER BY sort ASC, id ASC"
                : "SELECT * FROM list WHERE archived_at IS NULL ORDER BY sort ASC, id ASC"
            return try TaskList.fetchAll(db, sql: sql)
        }
    }

    @discardableResult
    public func createList(name: String, color: String? = "#6366F1", icon: String? = "list.bullet") throws -> TaskList {
        try db.writer.write { db in
            let maxSort = try Int.fetchOne(db, sql: "SELECT COALESCE(MAX(sort), -1) FROM list") ?? -1
            var list = TaskList(name: name, color: color, icon: icon, sort: maxSort + 1)
            try list.insert(db)
            return list
        }
    }

    public func archiveList(id: Int64, now: Date = .now) throws {
        let ts = Int64(now.timeIntervalSince1970)
        try db.writer.write { db in
            try db.execute(sql: "UPDATE list SET archived_at = ? WHERE id = ?", arguments: [ts, id])
        }
    }

    // MARK: - Tasks

    @discardableResult
    public func createTask(
        title: String,
        listId: Int64? = nil,
        day: String,
        notes: String? = nil,
        priority: Int = 0,
        estimatePomos: Int? = nil,
        link: String? = nil,
        recurrence: TaskRecurrence = .none,
        carriedFromId: Int64? = nil,
        rootId: Int64? = nil,
        now: Date = .now
    ) throws -> TaskItem {
        let ts = Int64(now.timeIntervalSince1970)
        return try db.writer.write { db in
            var item = TaskItem(
                listId: listId,
                title: title,
                notes: notes,
                day: day,
                status: .todo,
                priority: priority,
                estimatePomos: estimatePomos,
                link: link,
                recurrence: recurrence,
                carriedFromId: carriedFromId,
                rootId: rootId,
                createdAt: ts
            )
            try item.insert(db)
            if item.rootId == nil, let id = item.id {
                item.rootId = id
                try item.update(db)
            }
            if let id = item.id {
                var event = TaskEvent(taskId: id, ts: ts, kind: .created)
                try event.insert(db)
            }
            return item
        }
    }

    public func updateTask(_ task: TaskItem) throws {
        try db.writer.write { db in
            try task.update(db)
        }
    }

    public func deleteTask(id: Int64) throws {
        try db.writer.write { db in
            try db.execute(sql: "UPDATE task SET carried_from_id = NULL WHERE carried_from_id = ?", arguments: [id])
            try db.execute(sql: "UPDATE task SET root_id = id WHERE root_id = ? AND id != ?", arguments: [id, id])
            try db.execute(sql: "UPDATE task SET root_id = NULL WHERE id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM task WHERE id = ?", arguments: [id])
        }
    }

    public func fetchTasks(day: String) throws -> [TaskItem] {
        try db.writer.read { db in
            try TaskItem.fetchAll(
                db,
                sql: """
                    SELECT * FROM task
                    WHERE day = ?
                    ORDER BY
                        CASE status
                            WHEN 'doing' THEN 0
                            WHEN 'todo' THEN 1
                            WHEN 'done' THEN 2
                            WHEN 'skipped' THEN 3
                            ELSE 4
                        END ASC,
                        priority DESC,
                        created_at ASC
                    """,
                arguments: [day]
            )
        }
    }

    public func fetchUndoneTasks(day: String) throws -> [TaskItem] {
        try db.writer.read { db in
            try TaskItem.fetchAll(
                db,
                sql: """
                    SELECT * FROM task
                    WHERE day = ? AND status IN ('todo', 'doing')
                    ORDER BY
                        CASE status WHEN 'doing' THEN 0 ELSE 1 END ASC,
                        priority DESC,
                        created_at ASC
                    """,
                arguments: [day]
            )
        }
    }

    public func defaultActiveTask(day: String) throws -> TaskItem? {
        try fetchUndoneTasks(day: day).first
    }

    public func setTaskStatus(
        taskId: Int64,
        status: TaskStatus,
        skipReason: String? = nil,
        now: Date = .now
    ) throws {
        let ts = Int64(now.timeIntervalSince1970)
        try db.writer.write { db in
            guard var task = try TaskItem.fetchOne(db, key: taskId) else { return }
            let previous = task.taskStatus
            task.taskStatus = status
            if status == .done {
                task.completedAt = ts
                task.skipReason = nil
            } else if status == .skipped {
                task.completedAt = nil
                task.skipReason = skipReason
            } else {
                task.completedAt = nil
                if status != .abandoned { task.skipReason = nil }
            }
            try task.update(db)

            let eventKind: TaskEventKind
            switch status {
            case .doing: eventKind = .started
            case .done: eventKind = .done
            case .skipped: eventKind = .skipped
            case .abandoned: eventKind = .abandoned
            case .todo: eventKind = previous.isTerminal ? .reopened : .snoozed
            }
            var event = TaskEvent(taskId: taskId, ts: ts, kind: eventKind, meta: skipReason)
            try event.insert(db)
        }
    }

    // MARK: - Rollover, Recurrence, Skip Counts, Plan Your Day

    /// Carries forward unresolved `todo`/`doing` tasks from earlier days into `toDay`.
    @discardableResult
    public func rolloverUnfinishedTasks(toDay: String, now: Date = .now) throws -> [TaskItem] {
        let ts = Int64(now.timeIntervalSince1970)
        return try db.writer.write { db in
            let leftovers = try fetchUnresolvedLeftovers(in: db, beforeDay: toDay)
            var created: [TaskItem] = []
            for old in leftovers {
                guard let oldId = old.id else { continue }
                let rootId = old.rootId ?? oldId
                var carried = TaskItem(
                    listId: old.listId,
                    title: old.title,
                    notes: old.notes,
                    day: toDay,
                    status: .todo,
                    priority: old.priority,
                    estimatePomos: old.estimatePomos,
                    link: old.link,
                    recurrence: old.taskRecurrence,
                    carriedFromId: oldId,
                    rootId: rootId,
                    createdAt: ts
                )
                try carried.insert(db)
                var carriedEvent = TaskEvent(taskId: oldId, ts: ts, kind: .carried, meta: toDay)
                try carriedEvent.insert(db)
                if let newId = carried.id {
                    var createdEvent = TaskEvent(taskId: newId, ts: ts, kind: .created, meta: "rollover")
                    try createdEvent.insert(db)
                }
                created.append(carried)
            }
            return created
        }
    }

    /// Returns unresolved tasks from days earlier than `forDay` and recurring templates due on `forDay`.
    public func planYourDayPreview(
        forDay: String,
        calendar: Calendar = .current
    ) throws -> DayPlanPreview {
        try db.writer.read { db in
            let leftovers = try fetchUnresolvedLeftovers(in: db, beforeDay: forDay)
            let dueRecurring = try fetchDueRecurringTemplates(in: db, forDay: forDay, calendar: calendar)
            return DayPlanPreview(leftovers: leftovers, dueRecurring: dueRecurring)
        }
    }

    /// Instantiates due recurring tasks for `forDay` that don't already have an entry for that day.
    @discardableResult
    public func instantiateRecurringTasks(
        forDay: String,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> [TaskItem] {
        let ts = Int64(now.timeIntervalSince1970)
        return try db.writer.write { db in
            let due = try fetchDueRecurringTemplates(in: db, forDay: forDay, calendar: calendar)
            var created: [TaskItem] = []
            for tpl in due {
                var item = TaskItem(
                    listId: tpl.listId,
                    title: tpl.title,
                    day: forDay,
                    status: .todo,
                    priority: tpl.priority,
                    estimatePomos: tpl.estimatePomos,
                    link: tpl.link,
                    recurrence: tpl.recurrence,
                    carriedFromId: nil,
                    rootId: tpl.rootId,
                    createdAt: ts
                )
                try item.insert(db)
                if let id = item.id {
                    var ev = TaskEvent(taskId: id, ts: ts, kind: .created, meta: "recurring")
                    try ev.insert(db)
                }
                created.append(item)
            }
            return created
        }
    }

    /// Keeps an old task by carrying it to `toDay` (linking `carried_from_id` and `root_id`).
    @discardableResult
    public func keepLeftover(_ task: TaskItem, toDay: String, now: Date = .now) throws -> TaskItem {
        let ts = Int64(now.timeIntervalSince1970)
        return try db.writer.write { db in
            let rootId = task.rootId ?? task.id
            var carried = TaskItem(
                listId: task.listId,
                title: task.title,
                notes: task.notes,
                day: toDay,
                status: .todo,
                priority: task.priority,
                estimatePomos: task.estimatePomos,
                link: task.link,
                recurrence: task.taskRecurrence,
                carriedFromId: task.id,
                rootId: rootId,
                createdAt: ts
            )
            try carried.insert(db)
            if let oldId = task.id {
                var ev = TaskEvent(taskId: oldId, ts: ts, kind: .carried, meta: toDay)
                try ev.insert(db)
            }
            if let newId = carried.id {
                var ev = TaskEvent(taskId: newId, ts: ts, kind: .created, meta: "plan_keep")
                try ev.insert(db)
            }
            return carried
        }
    }

    public func chainMetadata(for tasks: [TaskItem]) throws -> [Int64: TaskChainMeta] {
        let roots = Set(tasks.compactMap { $0.rootId ?? $0.id })
        guard !roots.isEmpty else { return [:] }
        return try db.writer.read { db in
            var result: [Int64: TaskChainMeta] = [:]
            for root in roots {
                let count = try Int.fetchOne(
                    db,
                    sql: "SELECT COUNT(*) FROM task WHERE COALESCE(root_id, id) = ?",
                    arguments: [root]
                ) ?? 1
                let skips = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(*) FROM task_event te
                        JOIN task t ON t.id = te.task_id
                        WHERE COALESCE(t.root_id, t.id) = ? AND te.kind = 'skipped'
                        """,
                    arguments: [root]
                ) ?? 0
                let focusSec = try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COALESCE(SUM(s.active_sec), 0) FROM session s
                        JOIN task t ON t.id = s.task_id
                        WHERE COALESCE(t.root_id, t.id) = ? AND s.kind = 'work'
                        """,
                    arguments: [root]
                ) ?? 0
                result[root] = TaskChainMeta(
                    daysCarried: max(0, count - 1),
                    skipCount: skips,
                    focusSeconds: focusSec
                )
            }
            return result
        }
    }

    public func skipCount(forRootId rootId: Int64) throws -> Int {
        try db.writer.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM task_event te
                    JOIN task t ON t.id = te.task_id
                    WHERE COALESCE(t.root_id, t.id) = ? AND te.kind = 'skipped'
                    """,
                arguments: [rootId]
            ) ?? 0
        }
    }

    public func rolloverChainLength(forRootId rootId: Int64) throws -> Int {
        try db.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM task WHERE COALESCE(root_id, id) = ?",
                arguments: [rootId]
            ) ?? 0
        }
    }

    private func fetchUnresolvedLeftovers(in db: Database, beforeDay day: String) throws -> [TaskItem] {
        try TaskItem.fetchAll(
            db,
            sql: """
                SELECT * FROM task
                WHERE day < ?
                  AND status IN ('todo', 'doing')
                  AND id NOT IN (SELECT carried_from_id FROM task WHERE carried_from_id IS NOT NULL)
                ORDER BY day DESC, priority DESC, created_at ASC
                """,
            arguments: [day]
        )
    }

    private func fetchDueRecurringTemplates(in db: Database, forDay: String, calendar: Calendar) throws -> [RecurringTemplate] {
        guard let targetDate = HoltDay.date(fromKey: forDay, calendar: calendar) else { return [] }
        let weekday = calendar.component(.weekday, from: targetDate) // 1 = Sun, 2 = Mon .. 7 = Sat
        let rows = try TaskItem.fetchAll(
            db,
            sql: """
                SELECT * FROM task
                WHERE recurrence IS NOT NULL AND recurrence != 'none' AND day < ?
                ORDER BY day DESC, id DESC
                """,
            arguments: [forDay]
        )
        var seenRoots = Set<Int64>()
        var due: [RecurringTemplate] = []
        for row in rows {
            guard let id = row.id else { continue }
            let root = row.rootId ?? id
            guard !seenRoots.contains(root) else { continue }
            seenRoots.insert(root)

            // Skip if an instance for this root already exists on `forDay` (or is still open from earlier).
            let alreadyExists = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM task WHERE COALESCE(root_id, id) = ? AND (day = ? OR status IN ('todo', 'doing'))",
                arguments: [root, forDay]
            ) ?? 0
            guard alreadyExists == 0 else { continue }

            let rec = row.taskRecurrence
            let matches: Bool
            switch rec {
            case .none:
                matches = false
            case .daily:
                matches = true
            case .weekdays:
                matches = (2...6).contains(weekday)
            case .weekly:
                let originWeekday = calendar.component(.weekday, from: Date(timeIntervalSince1970: TimeInterval(row.createdAt)))
                matches = weekday == originWeekday
            }
            if matches {
                due.append(RecurringTemplate(
                    id: id,
                    rootId: root,
                    listId: row.listId,
                    title: row.title,
                    priority: row.priority,
                    estimatePomos: row.estimatePomos,
                    link: row.link,
                    recurrence: rec
                ))
            }
        }
        return due
    }

    // MARK: - Notes

    public func fetchDayNote(day: String) throws -> String {
        try db.writer.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT body FROM note WHERE day = ? AND task_id IS NULL AND session_id IS NULL ORDER BY updated_at DESC LIMIT 1",
                arguments: [day]
            ) ?? ""
        }
    }

    public func saveDayNote(day: String, body: String, now: Date = .now) throws {
        let ts = Int64(now.timeIntervalSince1970)
        try db.writer.write { db in
            if var existing = try NoteRecord.fetchOne(
                db,
                sql: "SELECT * FROM note WHERE day = ? AND task_id IS NULL AND session_id IS NULL ORDER BY updated_at DESC LIMIT 1",
                arguments: [day]
            ) {
                existing.body = body
                existing.updatedAt = ts
                try existing.update(db)
            } else if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                var note = NoteRecord(day: day, body: body, createdAt: ts, updatedAt: ts)
                try note.insert(db)
            }
        }
    }

    public func addSessionNote(day: String, sessionId: Int64, body: String, now: Date = .now) throws {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let ts = Int64(now.timeIntervalSince1970)
        try db.writer.write { db in
            var note = NoteRecord(day: day, sessionId: sessionId, body: trimmed, createdAt: ts, updatedAt: ts)
            try note.insert(db)
        }
    }

    public func fetchSessionNotes(day: String) throws -> [NoteRecord] {
        try db.writer.read { db in
            try NoteRecord.fetchAll(
                db,
                sql: "SELECT * FROM note WHERE day = ? AND session_id IS NOT NULL ORDER BY created_at DESC",
                arguments: [day]
            )
        }
    }

    // MARK: - Sessions & Pauses

    @discardableResult
    public func startSession(
        kind: SessionKind,
        plannedSec: Int,
        cycleIndex: Int,
        taskId: Int64?,
        startedBy: String = "user",
        now: Date = .now
    ) throws -> Int64 {
        let ts = Int64(now.timeIntervalSince1970)
        return try db.writer.write { db in
            var record = SessionRecord(
                kind: kind.dbKind,
                plannedSec: plannedSec,
                cycleIndex: cycleIndex,
                taskId: taskId,
                startedAt: ts,
                startedBy: startedBy
            )
            try record.insert(db)
            return record.id!
        }
    }

    public func pauseSession(sessionId: Int64, reason: PauseReason, at now: Date) throws {
        let ts = Int64(now.timeIntervalSince1970)
        try db.writer.write { db in
            var pause = SessionPauseRecord(sessionId: sessionId, startedAt: ts, reason: reason.rawValue)
            try pause.insert(db)
        }
    }

    public func resumeSession(sessionId: Int64, at now: Date) throws {
        let ts = Int64(now.timeIntervalSince1970)
        try db.writer.write { db in
            try db.execute(
                sql: "UPDATE session_pause SET ended_at = ? WHERE session_id = ? AND ended_at IS NULL",
                arguments: [ts, sessionId]
            )
        }
    }

    public func finishSession(
        sessionId: Int64,
        endReason: String,
        activeSec: Int,
        at now: Date
    ) throws {
        let ts = Int64(now.timeIntervalSince1970)
        try db.writer.write { db in
            try db.execute(
                sql: "UPDATE session_pause SET ended_at = ? WHERE session_id = ? AND ended_at IS NULL",
                arguments: [ts, sessionId]
            )
            try db.execute(
                sql: "UPDATE session SET ended_at = ?, end_reason = ?, active_sec = ? WHERE id = ?",
                arguments: [ts, endReason, max(0, activeSec), sessionId]
            )
        }
    }

    public func closeCrashedSessions(now: Date = .now) throws {
        let ts = Int64(now.timeIntervalSince1970)
        try db.writer.write { db in
            try db.execute(
                sql: "UPDATE session SET ended_at = ?, end_reason = 'crashed' WHERE ended_at IS NULL",
                arguments: [ts]
            )
        }
    }

    public func fetchSessions(day: String, rolloverHour: Int = 4, calendar: Calendar = .current) throws -> [SessionRecord] {
        guard let bounds = HoltDay.bounds(forKey: day, rolloverHour: rolloverHour, calendar: calendar) else { return [] }
        return try db.writer.read { db in
            try SessionRecord.fetchAll(
                db,
                sql: "SELECT * FROM session WHERE started_at >= ? AND started_at < ? ORDER BY started_at DESC",
                arguments: [bounds.start, bounds.end]
            )
        }
    }

    public func daySummary(day: String, rolloverHour: Int = 4, calendar: Calendar = .current) throws -> DayStatsSummary {
        let bounds = HoltDay.bounds(forKey: day, rolloverHour: rolloverHour, calendar: calendar) ?? (0, Int64.max)
        return try db.writer.read { db in
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
            let sessionsCompleted = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM session WHERE kind = 'work' AND end_reason = 'completed' AND started_at >= ? AND started_at < ?",
                arguments: [bounds.start, bounds.end]
            ) ?? 0
            let sessionsAbandoned = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM session WHERE kind = 'work' AND end_reason IN ('ended_early', 'converted_to_break', 'crashed') AND started_at >= ? AND started_at < ?",
                arguments: [bounds.start, bounds.end]
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
            return DayStatsSummary(
                day: day,
                focusSeconds: focusSec,
                breakSeconds: breakSec,
                sessionsCompleted: sessionsCompleted,
                sessionsAbandoned: sessionsAbandoned,
                tasksPlanned: tasksPlanned,
                tasksDone: tasksDone,
                tasksSkipped: tasksSkipped
            )
        }
    }

    public func daysWithActivity(inMonthPrefix prefix: String) throws -> Set<String> {
        try db.writer.read { db in
            let taskDays = try String.fetchAll(
                db,
                sql: "SELECT DISTINCT day FROM task WHERE day LIKE ?",
                arguments: ["\(prefix)%"]
            )
            let sessionStarts = try Int64.fetchAll(
                db,
                sql: "SELECT started_at FROM session WHERE kind = 'work'"
            )
            var result = Set(taskDays)
            for ts in sessionStarts {
                let key = HoltDay.key(for: Date(timeIntervalSince1970: TimeInterval(ts)))
                if key.hasPrefix(prefix) { result.insert(key) }
            }
            return result
        }
    }
}
