import Foundation
import GRDB

public struct AppSpanRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "app_span"

    public var id: Int64?
    public var bundleId: String
    public var appName: String
    public var windowTitle: String?
    public var startedAt: Int64
    public var endedAt: Int64
    public var sessionId: Int64?
    public var sessionKind: String?
    public var idle: Int
    public var category: String?

    public enum CodingKeys: String, CodingKey {
        case id, idle, category
        case bundleId = "bundle_id"
        case appName = "app_name"
        case windowTitle = "window_title"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case sessionId = "session_id"
        case sessionKind = "session_kind"
    }

    public init(
        id: Int64? = nil,
        bundleId: String,
        appName: String,
        windowTitle: String? = nil,
        startedAt: Int64,
        endedAt: Int64,
        sessionId: Int64? = nil,
        sessionKind: String? = nil,
        idle: Int = 0,
        category: String? = nil
    ) {
        self.id = id
        self.bundleId = bundleId
        self.appName = appName
        self.windowTitle = windowTitle
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sessionId = sessionId
        self.sessionKind = sessionKind
        self.idle = idle
        self.category = category
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct WebSpanRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "web_span"

    public var id: Int64?
    public var appSpanId: Int64?
    public var browser: String
    public var url: String?
    public var domain: String
    public var title: String?
    public var ytVideoId: String?
    public var ytChannel: String?
    public var ytCategory: String?
    public var startedAt: Int64
    public var endedAt: Int64
    public var sessionId: Int64?
    public var sessionKind: String?
    public var category: String?
    public var categorySource: String?

    public enum CodingKeys: String, CodingKey {
        case id, browser, url, domain, title, category
        case appSpanId = "app_span_id"
        case ytVideoId = "yt_video_id"
        case ytChannel = "yt_channel"
        case ytCategory = "yt_category"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case sessionId = "session_id"
        case sessionKind = "session_kind"
        case categorySource = "category_source"
    }

    public init(
        id: Int64? = nil,
        appSpanId: Int64? = nil,
        browser: String,
        url: String? = nil,
        domain: String,
        title: String? = nil,
        ytVideoId: String? = nil,
        ytChannel: String? = nil,
        ytCategory: String? = nil,
        startedAt: Int64,
        endedAt: Int64,
        sessionId: Int64? = nil,
        sessionKind: String? = nil,
        category: String? = nil,
        categorySource: String? = nil
    ) {
        self.id = id
        self.appSpanId = appSpanId
        self.browser = browser
        self.url = url
        self.domain = domain
        self.title = title
        self.ytVideoId = ytVideoId
        self.ytChannel = ytChannel
        self.ytCategory = ytCategory
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sessionId = sessionId
        self.sessionKind = sessionKind
        self.category = category
        self.categorySource = categorySource
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct ProcrastinationEventRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "procrastination_event"

    public var id: Int64?
    public var ts: Int64
    public var sessionId: Int64?
    public var kind: String
    public var subject: String?
    public var durationSec: Int?
    public var severity: Int

    public enum CodingKeys: String, CodingKey {
        case id, ts, kind, subject, severity
        case sessionId = "session_id"
        case durationSec = "duration_sec"
    }

    public init(
        id: Int64? = nil,
        ts: Int64,
        sessionId: Int64? = nil,
        kind: String,
        subject: String? = nil,
        durationSec: Int? = nil,
        severity: Int
    ) {
        self.id = id
        self.ts = ts
        self.sessionId = sessionId
        self.kind = kind
        self.subject = subject
        self.durationSec = durationSec
        self.severity = severity
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct SpanStore: Sendable {
    public let db: HoltDatabase

    public init(db: HoltDatabase) {
        self.db = db
    }

    public func writeBatch(appSpans: [AppSpanRecord], webSpans: [WebSpanRecord]) throws {
        guard !appSpans.isEmpty || !webSpans.isEmpty else { return }
        try db.writer.write { db in
            for span in appSpans {
                var copy = span
                try copy.insert(db)
            }
            for span in webSpans {
                var copy = span
                try copy.insert(db)
            }
        }
    }

    public func recordProcrastination(_ event: ProcrastinationEventRecord) throws {
        try db.writer.write { db in
            var copy = event
            try copy.insert(db)
        }
    }

    // MARK: - Rules

    public func fetchUserRules() throws -> [CategoryRuleRecord] {
        try db.writer.read { db in
            try CategoryRuleRecord.fetchAll(db, sql: "SELECT * FROM category_rule WHERE source = 'user' ORDER BY id DESC")
        }
    }

    @discardableResult
    public func upsertUserRule(kind: RuleKind, pattern: String, category: ActivityCategory) throws -> CategoryRuleRecord {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        return try db.writer.write { db in
            if var existing = try CategoryRuleRecord.fetchOne(
                db,
                sql: "SELECT * FROM category_rule WHERE kind = ? AND pattern = ?",
                arguments: [kind.rawValue, trimmed]
            ) {
                existing.category = category.rawValue
                existing.source = "user"
                try existing.update(db)
                return existing
            } else {
                var rule = CategoryRuleRecord(kind: kind, pattern: trimmed, category: category, source: "user")
                try rule.insert(db)
                return rule
            }
        }
    }

    public func deleteRule(id: Int64) throws {
        try db.writer.write { db in
            try db.execute(sql: "DELETE FROM category_rule WHERE id = ?", arguments: [id])
        }
    }

    /// Re-classifies recent spans matching a newly added "this is for work" rule.
    public func reclassifyMatching(kind: RuleKind, pattern: String, to category: ActivityCategory) throws {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        try db.writer.write { db in
            switch kind {
            case .bundle:
                try db.execute(
                    sql: "UPDATE app_span SET category = ? WHERE LOWER(bundle_id) = ?",
                    arguments: [category.rawValue, trimmed]
                )
            case .domain:
                try db.execute(
                    sql: "UPDATE web_span SET category = ?, category_source = 'user' WHERE LOWER(domain) = ? OR LOWER(domain) LIKE ?",
                    arguments: [category.rawValue, trimmed, "%.\(trimmed)"]
                )
            case .ytChannel:
                try db.execute(
                    sql: "UPDATE web_span SET category = ?, category_source = 'user' WHERE LOWER(yt_channel) = ?",
                    arguments: [category.rawValue, trimmed]
                )
            case .ytVideo:
                try db.execute(
                    sql: "UPDATE web_span SET category = ?, category_source = 'user' WHERE LOWER(yt_video_id) = ?",
                    arguments: [category.rawValue, trimmed]
                )
            case .urlRegex, .titleKeyword:
                break
            }
        }
    }

    // MARK: - Queries

    public func fetchAppSpans(day: String, rolloverHour: Int = 4, calendar: Calendar = .current) throws -> [AppSpanRecord] {
        guard let bounds = HoltDay.bounds(forKey: day, rolloverHour: rolloverHour, calendar: calendar) else { return [] }
        return try db.writer.read { db in
            try AppSpanRecord.fetchAll(
                db,
                sql: "SELECT * FROM app_span WHERE started_at >= ? AND started_at < ? AND idle = 0 ORDER BY started_at DESC",
                arguments: [bounds.start, bounds.end]
            )
        }
    }

    public func fetchWebSpans(day: String, rolloverHour: Int = 4, calendar: Calendar = .current) throws -> [WebSpanRecord] {
        guard let bounds = HoltDay.bounds(forKey: day, rolloverHour: rolloverHour, calendar: calendar) else { return [] }
        return try db.writer.read { db in
            try WebSpanRecord.fetchAll(
                db,
                sql: "SELECT * FROM web_span WHERE started_at >= ? AND started_at < ? ORDER BY started_at DESC",
                arguments: [bounds.start, bounds.end]
            )
        }
    }

    public func fetchProcrastinationEvents(day: String, rolloverHour: Int = 4, calendar: Calendar = .current) throws -> [ProcrastinationEventRecord] {
        guard let bounds = HoltDay.bounds(forKey: day, rolloverHour: rolloverHour, calendar: calendar) else { return [] }
        return try db.writer.read { db in
            try ProcrastinationEventRecord.fetchAll(
                db,
                sql: "SELECT * FROM procrastination_event WHERE ts >= ? AND ts < ? ORDER BY ts DESC",
                arguments: [bounds.start, bounds.end]
            )
        }
    }

    public func pruneOldRawSpans(olderThanDays days: Int, now: Date = .now) throws {
        let cutoff = Int64(now.timeIntervalSince1970) - Int64(days) * 86400
        try db.writer.write { db in
            try db.execute(sql: "DELETE FROM app_span WHERE ended_at < ?", arguments: [cutoff])
            try db.execute(sql: "DELETE FROM web_span WHERE ended_at < ?", arguments: [cutoff])
        }
    }
}
