import Foundation
import GRDB

public struct ExportBundle: Codable, Equatable, Sendable {
    public var exportedAt: Date
    public var lists: [TaskList]
    public var tasks: [TaskItem]
    public var taskEvents: [TaskEvent]
    public var notes: [NoteRecord]
    public var sessions: [SessionRecord]
    public var sessionPauses: [SessionPauseRecord]

    public init(
        exportedAt: Date = .now,
        lists: [TaskList],
        tasks: [TaskItem],
        taskEvents: [TaskEvent],
        notes: [NoteRecord],
        sessions: [SessionRecord],
        sessionPauses: [SessionPauseRecord]
    ) {
        self.exportedAt = exportedAt
        self.lists = lists
        self.tasks = tasks
        self.taskEvents = taskEvents
        self.notes = notes
        self.sessions = sessions
        self.sessionPauses = sessionPauses
    }
}

public enum DataPortability {
    // MARK: - JSON Export / Import

    public static func exportJSON(db: HoltDatabase, now: Date = .now) throws -> Data {
        let bundle = try db.writer.read { db in
            ExportBundle(
                exportedAt: now,
                lists: try TaskList.fetchAll(db, sql: "SELECT * FROM list ORDER BY id ASC"),
                tasks: try TaskItem.fetchAll(db, sql: "SELECT * FROM task ORDER BY id ASC"),
                taskEvents: try TaskEvent.fetchAll(db, sql: "SELECT * FROM task_event ORDER BY id ASC"),
                notes: try NoteRecord.fetchAll(db, sql: "SELECT * FROM note ORDER BY id ASC"),
                sessions: try SessionRecord.fetchAll(db, sql: "SELECT * FROM session ORDER BY id ASC"),
                sessionPauses: try SessionPauseRecord.fetchAll(db, sql: "SELECT * FROM session_pause ORDER BY id ASC")
            )
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(bundle)
    }

    public static func importJSON(_ data: Data, into db: HoltDatabase) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(ExportBundle.self, from: data)

        try db.writer.write { db in
            var listIdMap: [Int64: Int64] = [:]
            for item in bundle.lists {
                if let existing = try TaskList.fetchOne(db, sql: "SELECT * FROM list WHERE name = ? LIMIT 1", arguments: [item.name]),
                   let oldId = item.id, let newId = existing.id {
                    listIdMap[oldId] = newId
                } else {
                    var copy = item
                    copy.id = nil
                    try copy.insert(db)
                    if let oldId = item.id, let newId = copy.id {
                        listIdMap[oldId] = newId
                    }
                }
            }

            var taskIdMap: [Int64: Int64] = [:]
            for item in bundle.tasks {
                var copy = item
                copy.id = nil
                copy.listId = item.listId.flatMap { listIdMap[$0] }
                copy.carriedFromId = nil
                copy.rootId = nil
                try copy.insert(db)
                if let oldId = item.id, let newId = copy.id {
                    taskIdMap[oldId] = newId
                }
            }
            for item in bundle.tasks {
                guard let oldId = item.id, let newId = taskIdMap[oldId] else { continue }
                let mappedCarried = item.carriedFromId.flatMap { taskIdMap[$0] }
                let mappedRoot = item.rootId.flatMap { taskIdMap[$0] } ?? newId
                try db.execute(
                    sql: "UPDATE task SET carried_from_id = ?, root_id = ? WHERE id = ?",
                    arguments: [mappedCarried, mappedRoot, newId]
                )
            }

            for ev in bundle.taskEvents {
                guard let newTaskId = taskIdMap[ev.taskId] else { continue }
                var copy = ev
                copy.id = nil
                copy.taskId = newTaskId
                try copy.insert(db)
            }

            var sessionIdMap: [Int64: Int64] = [:]
            for s in bundle.sessions {
                var copy = s
                copy.id = nil
                copy.taskId = s.taskId.flatMap { taskIdMap[$0] }
                try copy.insert(db)
                if let oldId = s.id, let newId = copy.id {
                    sessionIdMap[oldId] = newId
                }
            }

            for p in bundle.sessionPauses {
                guard let newSessionId = sessionIdMap[p.sessionId] else { continue }
                var copy = p
                copy.id = nil
                copy.sessionId = newSessionId
                try copy.insert(db)
            }

            for n in bundle.notes {
                var copy = n
                copy.id = nil
                copy.taskId = n.taskId.flatMap { taskIdMap[$0] }
                copy.sessionId = n.sessionId.flatMap { sessionIdMap[$0] }
                try copy.insert(db)
            }
        }
    }

    // MARK: - CSV Export

    public static func exportTasksCSV(db: HoltDatabase) throws -> String {
        let rows = try db.writer.read { db in
            try TaskItem.fetchAll(db, sql: "SELECT * FROM task ORDER BY day DESC, id ASC")
        }
        var lines = ["id,day,list_id,title,status,priority,estimate_pomos,recurrence,carried_from_id,root_id,skip_reason"]
        for r in rows {
            let fields: [String] = [
                r.id.map(String.init) ?? "",
                r.day,
                r.listId.map(String.init) ?? "",
                r.title,
                r.status,
                String(r.priority),
                r.estimatePomos.map(String.init) ?? "",
                r.recurrence ?? "",
                r.carriedFromId.map(String.init) ?? "",
                r.rootId.map(String.init) ?? "",
                r.skipReason ?? "",
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func exportSessionsCSV(db: HoltDatabase) throws -> String {
        let rows = try db.writer.read { db in
            try SessionRecord.fetchAll(db, sql: "SELECT * FROM session ORDER BY started_at DESC")
        }
        var lines = ["id,kind,planned_sec,active_sec,cycle_index,task_id,started_at,ended_at,end_reason,started_by"]
        for r in rows {
            let fields: [String] = [
                r.id.map(String.init) ?? "",
                r.kind,
                String(r.plannedSec),
                String(r.activeSec),
                String(r.cycleIndex),
                r.taskId.map(String.init) ?? "",
                String(r.startedAt),
                r.endedAt.map(String.init) ?? "",
                r.endReason ?? "",
                r.startedBy,
            ]
            lines.append(fields.map(csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func csvEscape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    // MARK: - Backups & Deletion

    public static func defaultBackupDirectory() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Holt/Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @discardableResult
    public static func performBackup(
        db: HoltDatabase,
        toDirectory dir: URL? = nil,
        dayKey: String,
        keepCount: Int = 7
    ) throws -> URL {
        let backupDir = try dir ?? defaultBackupDirectory()
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        let target = backupDir.appendingPathComponent("holt-\(dayKey).sqlite")
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        let dest = try DatabaseQueue(path: target.path)
        try db.writer.backup(to: dest)

        let files = try FileManager.default.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.lastPathComponent.hasPrefix("holt-") && $0.pathExtension == "sqlite" }
        .sorted { $0.lastPathComponent > $1.lastPathComponent }

        if files.count > keepCount {
            for old in files.dropFirst(keepCount) {
                try? FileManager.default.removeItem(at: old)
            }
        }
        return target
    }

    public static func deleteHistory(db: HoltDatabase, fromDay: String, toDay: String) throws {
        guard let startBounds = HoltDay.bounds(forKey: fromDay),
              let endBounds = HoltDay.bounds(forKey: toDay) else { return }
        try db.writer.write { db in
            try db.execute(
                sql: "UPDATE task SET carried_from_id = NULL WHERE carried_from_id IN (SELECT id FROM task WHERE day >= ? AND day <= ?)",
                arguments: [fromDay, toDay]
            )
            try db.execute(
                sql: "UPDATE task SET root_id = id WHERE root_id IN (SELECT id FROM task WHERE day >= ? AND day <= ?) AND NOT (day >= ? AND day <= ?)",
                arguments: [fromDay, toDay, fromDay, toDay]
            )
            try db.execute(
                sql: "UPDATE task SET root_id = NULL WHERE day >= ? AND day <= ?",
                arguments: [fromDay, toDay]
            )
            try db.execute(sql: "DELETE FROM task WHERE day >= ? AND day <= ?", arguments: [fromDay, toDay])
            try db.execute(sql: "DELETE FROM note WHERE day >= ? AND day <= ?", arguments: [fromDay, toDay])
            try db.execute(sql: "DELETE FROM session WHERE started_at >= ? AND started_at < ?", arguments: [startBounds.start, endBounds.end])
            try db.execute(sql: "DELETE FROM app_span WHERE started_at >= ? AND started_at < ?", arguments: [startBounds.start, endBounds.end])
            try db.execute(sql: "DELETE FROM web_span WHERE started_at >= ? AND started_at < ?", arguments: [startBounds.start, endBounds.end])
            try db.execute(sql: "DELETE FROM daily_rollup WHERE day >= ? AND day <= ?", arguments: [fromDay, toDay])
            try db.execute(sql: "DELETE FROM hourly_rollup WHERE day >= ? AND day <= ?", arguments: [fromDay, toDay])
        }
    }

    public static func resetAllStats(db: HoltDatabase) throws {
        try db.writer.write { db in
            try db.execute(sql: """
                DELETE FROM session_pause;
                DELETE FROM session;
                DELETE FROM app_span;
                DELETE FROM web_span;
                DELETE FROM screen_observation;
                DELETE FROM procrastination_event;
                DELETE FROM holt_message;
                DELETE FROM daily_rollup;
                DELETE FROM hourly_rollup;
            """)
        }
    }
}
