import Foundation

/// The "Holt day": days roll over at `rolloverHour` (default 4 AM) local time, so a
/// session at 1 AM still counts toward the previous day.
public enum HoltDay {
    public static func key(for date: Date, rolloverHour: Int = 4, calendar: Calendar = .current) -> String {
        let shifted = date.addingTimeInterval(-TimeInterval(rolloverHour) * 3600)
        let c = calendar.dateComponents([.year, .month, .day], from: shifted)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Today's running totals (until the database lands in M2).
public struct DailyTally: Codable, Equatable, Sendable {
    public var day: String
    public var focusSeconds: TimeInterval
    public var sessionsCompleted: Int
    public var sessionsEndedEarly: Int

    public init(day: String) {
        self.day = day
        focusSeconds = 0
        sessionsCompleted = 0
        sessionsEndedEarly = 0
    }

    /// Records the work-related effects of one transition. `workSecondsDone` is the focused
    /// time of the work session *before* the transition (see `SessionState.workSecondsDone`).
    public mutating func record(_ effects: [SessionEffect], workSecondsDone: TimeInterval) {
        for effect in effects {
            switch effect {
            case .completed(.work):
                sessionsCompleted += 1
                focusSeconds += workSecondsDone
            case .endedEarly(.work):
                sessionsEndedEarly += 1
                focusSeconds += workSecondsDone
            default:
                break
            }
        }
    }
}
