import Foundation

/// The tone slider: 0 = polite, 0.5 = punchy & fun, 1 = strict.
public enum ToneBand: String, Codable, Sendable, CaseIterable {
    case polite, punchy, strict

    public init(value: Double) {
        switch value {
        case ..<0.34: self = .polite
        case ..<0.67: self = .punchy
        default: self = .strict
        }
    }

    public var title: String {
        switch self {
        case .polite: "Polite"
        case .punchy: "Punchy"
        case .strict: "Strict"
        }
    }
}

/// Template voice — always available, offline, deterministic. Phase 1 uses only
/// templates; a Phase 2 AI voice (PLAN P2.3) builds on the same triggers and falls back to these lines.
public enum Voice {
    public static func label(for action: SessionAction, tone: ToneBand) -> String {
        switch (action, tone) {
        case (.startWork, .polite): "Start focusing"
        case (.startWork, .punchy): "Get Shit Done"
        case (.startWork, .strict): "Work. Now."
        case (.takeBreak, _): "Take a break"
        case (.pause, _): "Pause"
        case (.resume, _): "Resume"
        case (.endSession, _): "End"
        case (.endBreak, _): "End break"
        case (.startNext, _): "Start"
        }
    }

    /// A line for a timer effect. `seed` picks a variant (pass something that changes).
    public static func line(for effect: SessionEffect, tone: ToneBand, seed: Int = 0) -> String? {
        let options = lines(for: effect, tone: tone)
        guard !options.isEmpty else { return nil }
        return options[Int(UInt(bitPattern: seed) % UInt(options.count))]
    }

    /// Every line Holt can say for an effect in a tone. All lines are original writing.
    public static func lines(for effect: SessionEffect, tone: ToneBand) -> [String] {
        switch effect {
        case .started(.work):
            switch tone {
            case .polite: return ["Focus session started. One block at a time.",
                                  "Timer's running. Close a tab or two and settle in."]
            case .punchy: return ["Deep work engaged. Distractions will be documented.",
                                  "The clock is running. So, theoretically, are you.",
                                  "Session started. Main-character energy, but make it productive."]
            case .strict: return ["Session started. Work. I'll be watching.",
                                  "The timer has begun. Excuses have not been scheduled."]
            }
        case .started(.shortBreak), .started(.longBreak):
            switch tone {
            case .polite: return ["Break time. Stretch, sip some water, rest your eyes.",
                                  "Nice work. Take a proper breather."]
            case .punchy: return ["Break time. Hydrate. Stare at a wall. Do not open Reddit.",
                                  "Recess. Touch grass, metaphorically or otherwise.",
                                  "Break commenced. Thou hast earned a brief respite."]
            case .strict: return ["Break started. It ends when the timer says, not when you feel like it.",
                                  "Rest. Efficiently."]
            }
        case .completed(.work):
            switch tone {
            case .polite: return ["Session complete. Nicely done — take a breather.",
                                  "That's one more focused block in the books. Well earned."]
            case .punchy: return ["Session complete. No collapse into digital nonsense. Growth.",
                                  "A full session of actual work. I'm documenting this for posterity.",
                                  "Focus block done. Lowkey impressive. I will deny saying that."]
            case .strict: return ["Session complete. Acceptable. Do it again.",
                                  "One down. Excellence is a habit, not a single event."]
            }
        case .completed(.shortBreak), .completed(.longBreak):
            switch tone {
            case .polite: return ["Break's over whenever you're ready."]
            case .punchy: return ["Break concluded. The mountain did not climb itself in your absence.",
                                  "Recess has ended. Hie thee back to thy desk."]
            case .strict: return ["Break over. Back to it.",
                                  "Rest complete. The work remains exactly where you left it."]
            }
        case .endedEarly(.work):
            switch tone {
            case .polite: return ["Session ended early. That's okay — start another when you can."]
            case .punchy: return ["Ended early. Noted. Everything is noted.",
                                  "You abandoned the session. It's giving 'commitment issues'."]
            case .strict: return ["Session abandoned. This will appear in the record.",
                                  "Ended early. Disappointing, but not surprising."]
            }
        case .endedEarly(.shortBreak), .endedEarly(.longBreak):
            switch tone {
            case .polite: return ["Back already? Ready when you are."]
            case .punchy: return ["Break cut short. Voluntarily. I'm almost impressed."]
            case .strict: return ["Break ended early. Good. Proceed."]
            }
        case .paused(.user):
            switch tone {
            case .polite: return ["Paused. Take the time you need."]
            case .punchy: return ["Paused. The clock respects your decision. I reserve judgment.",
                                  "Paused. The mountain will wait. Barely."]
            case .strict: return ["Paused. Make it brief."]
            }
        case .paused(.idle):
            switch tone {
            case .polite: return ["No activity for a while, so I paused the session."]
            case .punchy: return ["Paused. You've been motionless long enough for me to assume meditation.",
                                  "No input detected. Deep thought or a nap. I've paused, just in case."]
            case .strict: return ["Paused for inactivity. Idle minutes do not count. Ever."]
            }
        case .paused(.sleep), .paused(.lock):
            switch tone {
            case .polite: return ["You stepped away, so the session is paused."]
            case .punchy: return ["Paused while you were away. The work, sadly, waited for you."]
            case .strict: return ["Paused. Time away from the desk is not focus time."]
            }
        case .resumed:
            switch tone {
            case .polite: return ["Resumed. Welcome back."]
            case .punchy: return ["Resumed. Try to look busy.",
                                  "And we're back. Forsooth."]
            case .strict: return ["Resumed. Continue."]
            }
        }
    }
}
