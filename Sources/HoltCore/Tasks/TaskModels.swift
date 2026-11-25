import Foundation
import GRDB

public struct TaskList: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "list"

    public var id: Int64?
    public var name: String
    public var color: String?
    public var icon: String?
    public var sort: Int
    public var archivedAt: Int64?

    public enum CodingKeys: String, CodingKey {
        case id, name, color, icon, sort
        case archivedAt = "archived_at"
    }

    public init(id: Int64? = nil, name: String, color: String? = "#6366F1", icon: String? = "list.bullet", sort: Int = 0, archivedAt: Int64? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.icon = icon
        self.sort = sort
        self.archivedAt = archivedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case todo, doing, done, skipped, abandoned

    public var isTerminal: Bool {
        self == .done || self == .skipped || self == .abandoned
    }
}

public enum TaskRecurrence: String, Codable, Sendable, CaseIterable {
    case none, daily, weekdays, weekly

    public var title: String {
        switch self {
        case .none: "Once"
        case .daily: "Daily"
        case .weekdays: "Weekdays"
        case .weekly: "Weekly"
        }
    }
}

public struct TaskItem: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "task"

    public var id: Int64?
    public var listId: Int64?
    public var title: String
    public var notes: String?
    public var day: String
    public var status: String
    public var priority: Int
    public var estimatePomos: Int?
    public var link: String?
    public var recurrence: String?
    public var carriedFromId: Int64?
    public var rootId: Int64?
    public var createdAt: Int64
    public var completedAt: Int64?
    public var skipReason: String?

    public enum CodingKeys: String, CodingKey {
        case id, title, notes, day, status, priority, link, recurrence
        case listId = "list_id"
        case estimatePomos = "estimate_pomos"
        case carriedFromId = "carried_from_id"
        case rootId = "root_id"
        case createdAt = "created_at"
        case completedAt = "completed_at"
        case skipReason = "skip_reason"
    }

    public init(
        id: Int64? = nil,
        listId: Int64? = nil,
        title: String,
        notes: String? = nil,
        day: String,
        status: TaskStatus = .todo,
        priority: Int = 0,
        estimatePomos: Int? = nil,
        link: String? = nil,
        recurrence: TaskRecurrence = .none,
        carriedFromId: Int64? = nil,
        rootId: Int64? = nil,
        createdAt: Int64,
        completedAt: Int64? = nil,
        skipReason: String? = nil
    ) {
        self.id = id
        self.listId = listId
        self.title = title
        self.notes = notes
        self.day = day
        self.status = status.rawValue
        self.priority = priority
        self.estimatePomos = estimatePomos
        self.link = link
        self.recurrence = recurrence == .none ? nil : recurrence.rawValue
        self.carriedFromId = carriedFromId
        self.rootId = rootId
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.skipReason = skipReason
    }

    public var taskStatus: TaskStatus {
        get { TaskStatus(rawValue: status) ?? .todo }
        set { status = newValue.rawValue }
    }

    public var taskRecurrence: TaskRecurrence {
        get { recurrence.flatMap(TaskRecurrence.init(rawValue:)) ?? .none }
        set { recurrence = newValue == .none ? nil : newValue.rawValue }
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public enum TaskEventKind: String, Codable, Sendable {
    case created, started, done, skipped, reopened, carried, snoozed, abandoned
}

public struct TaskEvent: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "task_event"

    public var id: Int64?
    public var taskId: Int64
    public var ts: Int64
    public var kind: String
    public var meta: String?

    public enum CodingKeys: String, CodingKey {
        case id, ts, kind, meta
        case taskId = "task_id"
    }

    public init(id: Int64? = nil, taskId: Int64, ts: Int64, kind: TaskEventKind, meta: String? = nil) {
        self.id = id
        self.taskId = taskId
        self.ts = ts
        self.kind = kind.rawValue
        self.meta = meta
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct NoteRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "note"

    public var id: Int64?
    public var day: String
    public var taskId: Int64?
    public var sessionId: Int64?
    public var body: String
    public var createdAt: Int64
    public var updatedAt: Int64

    public enum CodingKeys: String, CodingKey {
        case id, day, body
        case taskId = "task_id"
        case sessionId = "session_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(
        id: Int64? = nil,
        day: String,
        taskId: Int64? = nil,
        sessionId: Int64? = nil,
        body: String,
        createdAt: Int64,
        updatedAt: Int64
    ) {
        self.id = id
        self.day = day
        self.taskId = taskId
        self.sessionId = sessionId
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct SessionRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "session"

    public var id: Int64?
    public var kind: String
    public var plannedSec: Int
    public var cycleIndex: Int
    public var taskId: Int64?
    public var startedAt: Int64
    public var endedAt: Int64?
    public var endReason: String?
    public var activeSec: Int
    public var startedBy: String

    public enum CodingKeys: String, CodingKey {
        case id, kind
        case plannedSec = "planned_sec"
        case cycleIndex = "cycle_index"
        case taskId = "task_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case endReason = "end_reason"
        case activeSec = "active_sec"
        case startedBy = "started_by"
    }

    public init(
        id: Int64? = nil,
        kind: String,
        plannedSec: Int,
        cycleIndex: Int,
        taskId: Int64? = nil,
        startedAt: Int64,
        endedAt: Int64? = nil,
        endReason: String? = nil,
        activeSec: Int = 0,
        startedBy: String = "user"
    ) {
        self.id = id
        self.kind = kind
        self.plannedSec = plannedSec
        self.cycleIndex = cycleIndex
        self.taskId = taskId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.endReason = endReason
        self.activeSec = activeSec
        self.startedBy = startedBy
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct SessionPauseRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "session_pause"

    public var id: Int64?
    public var sessionId: Int64
    public var startedAt: Int64
    public var endedAt: Int64?
    public var reason: String

    public enum CodingKeys: String, CodingKey {
        case id, reason
        case sessionId = "session_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }

    public init(id: Int64? = nil, sessionId: Int64, startedAt: Int64, endedAt: Int64? = nil, reason: String) {
        self.id = id
        self.sessionId = sessionId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.reason = reason
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct SettingRecord: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public static let databaseTableName = "setting"
    public var key: String
    public var value: String

    public init(key: String, value: String) {
        self.key = key
        self.value = value
    }
}
