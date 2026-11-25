import Foundation

/// User-configurable Pomodoro settings.
public struct TimerConfig: Equatable, Codable, Sendable {
    public var workSeconds: TimeInterval
    public var shortBreakSeconds: TimeInterval
    public var longBreakSeconds: TimeInterval
    /// Completed work sessions before a long break is due.
    public var sessionsBeforeLongBreak: Int
    public var autoStartBreak: Bool
    public var autoStartWork: Bool

    public init(
        workSeconds: TimeInterval = 25 * 60,
        shortBreakSeconds: TimeInterval = 5 * 60,
        longBreakSeconds: TimeInterval = 20 * 60,
        sessionsBeforeLongBreak: Int = 4,
        autoStartBreak: Bool = true,
        autoStartWork: Bool = false
    ) {
        self.workSeconds = workSeconds
        self.shortBreakSeconds = shortBreakSeconds
        self.longBreakSeconds = longBreakSeconds
        self.sessionsBeforeLongBreak = max(1, sessionsBeforeLongBreak)
        self.autoStartBreak = autoStartBreak
        self.autoStartWork = autoStartWork
    }

    public static let `default` = TimerConfig()

    public func duration(of kind: SessionKind) -> TimeInterval {
        switch kind {
        case .work: workSeconds
        case .shortBreak: shortBreakSeconds
        case .longBreak: longBreakSeconds
        }
    }
}
