import Foundation

/// Everything the user can change in Settings. Decoding falls back to the default for any
/// missing key, so adding a setting never breaks previously saved data.
public struct AppSettings: Equatable, Sendable {
    public static let workRange = 5...180
    public static let shortBreakRange = 1...60
    public static let longBreakRange = 5...120
    public static let cycleRange = 2...12
    public static let idleRange = 1...30

    public var workMinutes = 25
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 20
    public var sessionsBeforeLongBreak = 4
    public var autoStartBreak = true
    public var autoStartWork = false
    public var pauseWhenIdle = true
    public var idleMinutes = 5
    public var keyboardCountsAsActivity = true
    public var playSounds = true
    public var showNotifications = true
    public var jellyHaptics = true

    public init() {}

    public var timerConfig: TimerConfig {
        TimerConfig(
            workSeconds: TimeInterval(workMinutes * 60),
            shortBreakSeconds: TimeInterval(shortBreakMinutes * 60),
            longBreakSeconds: TimeInterval(longBreakMinutes * 60),
            sessionsBeforeLongBreak: sessionsBeforeLongBreak,
            autoStartBreak: autoStartBreak,
            autoStartWork: autoStartWork
        )
    }

    /// Default length in minutes for a session of `kind`.
    public func minutes(for kind: SessionKind) -> Int {
        switch kind {
        case .work: workMinutes
        case .shortBreak: shortBreakMinutes
        case .longBreak: longBreakMinutes
        }
    }

    /// Every numeric setting forced into its allowed range.
    public func clamped() -> AppSettings {
        var s = self
        s.workMinutes = Self.clamp(workMinutes, Self.workRange)
        s.shortBreakMinutes = Self.clamp(shortBreakMinutes, Self.shortBreakRange)
        s.longBreakMinutes = Self.clamp(longBreakMinutes, Self.longBreakRange)
        s.sessionsBeforeLongBreak = Self.clamp(sessionsBeforeLongBreak, Self.cycleRange)
        s.idleMinutes = Self.clamp(idleMinutes, Self.idleRange)
        return s
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

extension AppSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case workMinutes, shortBreakMinutes, longBreakMinutes, sessionsBeforeLongBreak
        case autoStartBreak, autoStartWork, pauseWhenIdle, idleMinutes, keyboardCountsAsActivity
        case playSounds, showNotifications, jellyHaptics
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        workMinutes = try c.decodeIfPresent(Int.self, forKey: .workMinutes) ?? d.workMinutes
        shortBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .shortBreakMinutes) ?? d.shortBreakMinutes
        longBreakMinutes = try c.decodeIfPresent(Int.self, forKey: .longBreakMinutes) ?? d.longBreakMinutes
        sessionsBeforeLongBreak = try c.decodeIfPresent(Int.self, forKey: .sessionsBeforeLongBreak) ?? d.sessionsBeforeLongBreak
        autoStartBreak = try c.decodeIfPresent(Bool.self, forKey: .autoStartBreak) ?? d.autoStartBreak
        autoStartWork = try c.decodeIfPresent(Bool.self, forKey: .autoStartWork) ?? d.autoStartWork
        pauseWhenIdle = try c.decodeIfPresent(Bool.self, forKey: .pauseWhenIdle) ?? d.pauseWhenIdle
        idleMinutes = try c.decodeIfPresent(Int.self, forKey: .idleMinutes) ?? d.idleMinutes
        keyboardCountsAsActivity = try c.decodeIfPresent(Bool.self, forKey: .keyboardCountsAsActivity) ?? d.keyboardCountsAsActivity
        playSounds = try c.decodeIfPresent(Bool.self, forKey: .playSounds) ?? d.playSounds
        showNotifications = try c.decodeIfPresent(Bool.self, forKey: .showNotifications) ?? d.showNotifications
        jellyHaptics = try c.decodeIfPresent(Bool.self, forKey: .jellyHaptics) ?? d.jellyHaptics
    }
}
