import Foundation

public enum SoundChoice: String, Codable, Sendable, CaseIterable {
    case holt, system, custom

    public var title: String {
        switch self {
        case .holt: "Holt chime"
        case .system: "macOS system"
        case .custom: "Custom file"
        }
    }
}

/// A global hotkey using Carbon virtual keyCode + Carbon modifier flags.
public struct HotkeyShortcut: Codable, Equatable, Sendable {
    public static let cmdMask: UInt32 = 1 << 8
    public static let shiftMask: UInt32 = 1 << 9
    public static let optionMask: UInt32 = 1 << 11
    public static let controlMask: UInt32 = 1 << 12

    public static let defaultStartPause = HotkeyShortcut(keyCode: 49, modifiers: controlMask | optionMask) // ⌃⌥Space
    public static let defaultTakeBreak = HotkeyShortcut(keyCode: 11, modifiers: controlMask | optionMask)  // ⌃⌥B
    public static let defaultEndSession = HotkeyShortcut(keyCode: 14, modifiers: controlMask | optionMask) // ⌃⌥E

    public var keyCode: UInt32
    public var modifiers: UInt32
    public var isEnabled: Bool

    public init(keyCode: UInt32, modifiers: UInt32, isEnabled: Bool = true) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isEnabled = isEnabled
    }

    public var displayString: String {
        var out = ""
        if modifiers & Self.controlMask != 0 { out += "⌃" }
        if modifiers & Self.optionMask != 0 { out += "⌥" }
        if modifiers & Self.shiftMask != 0 { out += "⇧" }
        if modifiers & Self.cmdMask != 0 { out += "⌘" }
        out += Self.keyLabel(for: keyCode)
        return out
    }

    public static func keyLabel(for keyCode: UInt32) -> String {
        switch keyCode {
        case 49: "Space"
        case 36: "↩"
        case 53: "⎋"
        case 48: "⇥"
        case 0: "A"
        case 11: "B"
        case 8: "C"
        case 2: "D"
        case 14: "E"
        case 3: "F"
        case 5: "G"
        case 4: "H"
        case 34: "I"
        case 38: "J"
        case 40: "K"
        case 37: "L"
        case 46: "M"
        case 45: "N"
        case 31: "O"
        case 35: "P"
        case 12: "Q"
        case 15: "R"
        case 1: "S"
        case 17: "T"
        case 32: "U"
        case 9: "V"
        case 13: "W"
        case 7: "X"
        case 16: "Y"
        case 6: "Z"
        case 18: "1"
        case 19: "2"
        case 20: "3"
        case 21: "4"
        case 23: "5"
        case 22: "6"
        case 26: "7"
        case 28: "8"
        case 25: "9"
        case 29: "0"
        default: "#\(keyCode)"
        }
    }
}

/// Everything the user can change in Settings. Decoding falls back to the default for any
/// missing key, so adding a setting never breaks previously saved data.
public struct AppSettings: Equatable, Sendable {
    public static let workRange = 5...180
    public static let shortBreakRange = 1...60
    public static let longBreakRange = 5...120
    public static let cycleRange = 2...12
    public static let idleRange = 1...30
    public static let workingTooLongRange = 30...240

    public var workMinutes = 25
    public var shortBreakMinutes = 5
    public var longBreakMinutes = 20
    public var sessionsBeforeLongBreak = 4
    public var autoStartBreak = true
    public var autoStartWork = false
    public var pauseWhenIdle = true
    public var idleMinutes = 5
    public var keyboardCountsAsActivity = true
    public var nudgeWorkingTooLong = true
    public var workingTooLongMinutes = 90
    public var playSounds = true
    public var soundVolume = 0.8
    public var soundChoice: SoundChoice = .holt
    public var customSoundPath: String?
    public var showNotifications = true
    public var jellyHaptics = true
    public var hotkeysEnabled = true
    public var startPauseHotkey: HotkeyShortcut = .defaultStartPause
    public var breakHotkey: HotkeyShortcut = .defaultTakeBreak
    public var endHotkey: HotkeyShortcut = .defaultEndSession

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
        s.workingTooLongMinutes = Self.clamp(workingTooLongMinutes, Self.workingTooLongRange)
        s.soundVolume = min(max(soundVolume.isFinite ? soundVolume : 0.8, 0.0), 1.0)
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
        case nudgeWorkingTooLong, workingTooLongMinutes
        case playSounds, soundVolume, soundChoice, customSoundPath
        case showNotifications, jellyHaptics
        case hotkeysEnabled, startPauseHotkey, breakHotkey, endHotkey
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
        nudgeWorkingTooLong = try c.decodeIfPresent(Bool.self, forKey: .nudgeWorkingTooLong) ?? d.nudgeWorkingTooLong
        workingTooLongMinutes = try c.decodeIfPresent(Int.self, forKey: .workingTooLongMinutes) ?? d.workingTooLongMinutes
        playSounds = try c.decodeIfPresent(Bool.self, forKey: .playSounds) ?? d.playSounds
        soundVolume = try c.decodeIfPresent(Double.self, forKey: .soundVolume) ?? d.soundVolume
        soundChoice = try c.decodeIfPresent(SoundChoice.self, forKey: .soundChoice) ?? d.soundChoice
        customSoundPath = try c.decodeIfPresent(String.self, forKey: .customSoundPath) ?? d.customSoundPath
        showNotifications = try c.decodeIfPresent(Bool.self, forKey: .showNotifications) ?? d.showNotifications
        jellyHaptics = try c.decodeIfPresent(Bool.self, forKey: .jellyHaptics) ?? d.jellyHaptics
        hotkeysEnabled = try c.decodeIfPresent(Bool.self, forKey: .hotkeysEnabled) ?? d.hotkeysEnabled
        startPauseHotkey = try c.decodeIfPresent(HotkeyShortcut.self, forKey: .startPauseHotkey) ?? d.startPauseHotkey
        breakHotkey = try c.decodeIfPresent(HotkeyShortcut.self, forKey: .breakHotkey) ?? d.breakHotkey
        endHotkey = try c.decodeIfPresent(HotkeyShortcut.self, forKey: .endHotkey) ?? d.endHotkey
    }
}
