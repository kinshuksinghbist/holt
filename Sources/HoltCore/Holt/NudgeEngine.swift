import Foundation
import GRDB

public enum NudgeOutcome: String, Codable, Sendable {
    case acted, snoozed, dismissed, ignored
}

public struct HoltMessageRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "holt_message"

    public var id: Int64?
    public var ts: Int64
    public var channel: String
    public var trigger: String
    public var tone: Double
    public var templateId: String
    public var text: String
    public var deliveredAt: Int64?
    public var outcome: String?

    public enum CodingKeys: String, CodingKey {
        case id, ts, channel, trigger, tone, text, outcome
        case templateId = "template_id"
        case deliveredAt = "delivered_at"
    }

    public init(
        id: Int64? = nil,
        ts: Int64,
        channel: String,
        trigger: String,
        tone: Double,
        templateId: String,
        text: String,
        deliveredAt: Int64? = nil,
        outcome: String? = nil
    ) {
        self.id = id
        self.ts = ts
        self.channel = channel
        self.trigger = trigger
        self.tone = tone
        self.templateId = templateId
        self.text = text
        self.deliveredAt = deliveredAt
        self.outcome = outcome
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct MessageStore: Sendable {
    public let db: HoltDatabase

    public init(db: HoltDatabase) {
        self.db = db
    }

    @discardableResult
    public func log(_ message: HoltMessageRecord) throws -> HoltMessageRecord {
        try db.writer.write { db in
            var copy = message
            try copy.insert(db)
            return copy
        }
    }

    public func updateOutcome(id: Int64, outcome: NudgeOutcome) throws {
        try db.writer.write { db in
            try db.execute(
                sql: "UPDATE holt_message SET outcome = ? WHERE id = ?",
                arguments: [outcome.rawValue, id]
            )
        }
    }

    public func countDeliveredInLastHour(now: Date = .now) throws -> Int {
        let cutoff = Int64(now.addingTimeInterval(-3600).timeIntervalSince1970)
        return try db.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM holt_message WHERE channel = 'notification' AND delivered_at >= ?",
                arguments: [cutoff]
            ) ?? 0
        }
    }

    public func lastDeliveredAt(trigger: VoiceTrigger) throws -> Date? {
        try db.writer.read { db in
            guard let ts = try Int64.fetchOne(
                db,
                sql: "SELECT MAX(delivered_at) FROM holt_message WHERE channel = 'notification' AND trigger = ?",
                arguments: [trigger.rawValue]
            ) else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(ts))
        }
    }

    public func fetchRecent(limit: Int = 50) throws -> [HoltMessageRecord] {
        try db.writer.read { db in
            try HoltMessageRecord.fetchAll(
                db,
                sql: "SELECT * FROM holt_message ORDER BY ts DESC LIMIT ?",
                arguments: [limit]
            )
        }
    }
}

public enum NudgePolicy {
    public static func cooldownSeconds(for trigger: VoiceTrigger) -> TimeInterval {
        switch trigger {
        case .distraction, .ytEntertainment: 60
        case .noSessionActive: 30 * 60
        case .hourlyReminder: 40 * 60
        case .workingTooLong: 20 * 60
        case .morningBrief, .eodSummary: 20 * 3600
        case .weeklyReview: 6 * 86400
        default: 0
        }
    }

    public static func isQuietHour(date: Date, startHour: Int, endHour: Int, calendar: Calendar = .current) -> Bool {
        let hour = calendar.component(.hour, from: date)
        if startHour == endHour { return false }
        if startHour < endHour {
            return hour >= startHour && hour < endHour
        } else {
            return hour >= startHour || hour < endHour
        }
    }

    public static func shouldDeliverNotification(
        trigger: VoiceTrigger,
        settings: AppSettings,
        now: Date,
        isSystemFocusActive: Bool,
        snoozedAllUntil: Date?,
        deliveredLastHour: Int,
        lastTriggerDeliveredAt: Date?,
        calendar: Calendar = .current
    ) -> Bool {
        guard settings.showNotifications else { return false }
        if let snoozedAllUntil, now < snoozedAllUntil { return false }
        if settings.respectSystemFocus && isSystemFocusActive { return false }
        if settings.quietHoursEnabled && isQuietHour(date: now, startHour: settings.quietStartHour, endHour: settings.quietEndHour, calendar: calendar) {
            return false
        }
        // Always allow critical user-initiated/direct session events? Still respect per-hour cap for nudges:
        let isNudge = trigger == .hourlyReminder || trigger == .noSessionActive || trigger == .distraction
            || trigger == .ytEntertainment || trigger == .workingTooLong
            || trigger == .morningBrief || trigger == .eodSummary || trigger == .weeklyReview
        if isNudge && deliveredLastHour >= settings.maxNudgesPerHour {
            return false
        }
        let cooldown = cooldownSeconds(for: trigger)
        if cooldown > 0, let last = lastTriggerDeliveredAt, now.timeIntervalSince(last) < cooldown {
            return false
        }
        return true
    }

    /// Computes reminder interval in seconds. "Varied" jitters between 40 and 90 min scaled by tone.
    public static func nextReminderIntervalSeconds(
        cadence: ReminderCadence,
        tone: ToneBand,
        jitterUnit: Double = 0.5
    ) -> TimeInterval {
        let clampedJitter = min(max(jitterUnit, 0), 1)
        let baseMinutes: Double
        switch cadence {
        case .hourly:
            baseMinutes = 60.0
        case .varied:
            baseMinutes = 40.0 + 50.0 * clampedJitter
        }
        let multiplier: Double
        switch tone {
        case .polite: multiplier = 1.67 // 0.6x cadence
        case .punchy: multiplier = 1.0
        case .strict: multiplier = 0.67 // 1.5x cadence
        }
        return (baseMinutes * multiplier) * 60.0
    }
}

public struct FocusBlockSchedule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var label: String
    /// Calendar weekday numbers (1 = Sunday ... 7 = Saturday).
    public var weekdays: Set<Int>
    public var startHour: Int
    public var startMinute: Int
    public var endHour: Int
    public var endMinute: Int
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        label: String = "Morning Focus",
        weekdays: Set<Int> = [2, 3, 4, 5, 6],
        startHour: Int = 10,
        startMinute: Int = 0,
        endHour: Int = 12,
        endMinute: Int = 0,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.label = label
        self.weekdays = weekdays
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.isEnabled = isEnabled
    }

    public func matches(date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return false }
        let comps = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let wd = comps.weekday, let h = comps.hour, let m = comps.minute else { return false }
        guard weekdays.contains(wd) else { return false }
        let nowMin = h * 60 + m
        let startMin = startHour * 60 + startMinute
        let endMin = endHour * 60 + endMinute
        return nowMin >= startMin && nowMin < endMin
    }
}

public enum AutoSessionEvent: Equatable, Sendable {
    case promptDetectedWork
    case startDetectedWork
    case startScheduledBlock(String)
}

/// Evaluates automatic work session triggers (detected productive work & scheduled blocks).
public struct AutoSessionMonitor: Equatable, Sendable {
    public private(set) var productiveSince: Date?
    public private(set) var pendingStartAt: Date?
    public private(set) var detectedWorkSnoozedUntil: Date?

    public init() {}

    public mutating func snoozeDetectedWork(now: Date, hours: Int = 1) {
        productiveSince = nil
        pendingStartAt = nil
        detectedWorkSnoozedUntil = now.addingTimeInterval(TimeInterval(hours * 3600))
    }

    public mutating func cancelPending() {
        productiveSince = nil
        pendingStartAt = nil
    }

    public mutating func update(
        phase: SessionPhase,
        isProductiveActivity: Bool,
        isIdle: Bool,
        settings: AppSettings,
        now: Date,
        calendar: Calendar = .current
    ) -> AutoSessionEvent? {
        guard phase == .idle, !isIdle else {
            productiveSince = nil
            pendingStartAt = nil
            return nil
        }

        // 1. Scheduled focus blocks
        for block in settings.scheduledFocusBlocks where block.matches(date: now, calendar: calendar) {
            productiveSince = nil
            pendingStartAt = nil
            return .startScheduledBlock(block.label)
        }

        // 2. Detected productive work (>= 2 min continuous, then 10 s grace countdown)
        guard settings.autoSessionDetectedWork else {
            productiveSince = nil
            pendingStartAt = nil
            return nil
        }
        if let snoozed = detectedWorkSnoozedUntil, now < snoozed {
            return nil
        }
        if let pending = pendingStartAt {
            if now >= pending {
                pendingStartAt = nil
                productiveSince = nil
                return .startDetectedWork
            }
            return nil
        }

        if isProductiveActivity {
            if productiveSince == nil {
                productiveSince = now
            } else if let since = productiveSince, now.timeIntervalSince(since) >= 120 {
                pendingStartAt = now.addingTimeInterval(10)
                return .promptDetectedWork
            }
        } else {
            productiveSince = nil
        }
        return nil
    }
}
