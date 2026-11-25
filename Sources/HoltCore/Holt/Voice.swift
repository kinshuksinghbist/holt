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
        case (.pause, _): "Pause session"
        case (.resume, _): "Resume"
        case (.endSession, _): "End session"
        case (.endBreak, _): "End break"
        case (.startNext, _): "Start"
        }
    }

    /// A line for a timer effect. `seed` picks a variant (pass something that changes, e.g. a session count).
    public static func line(for effect: SessionEffect, tone: ToneBand, seed: Int = 0) -> String? {
        let options: [String]
        switch (effect, tone) {
        case (.completed(.work), .polite):
            options = ["Session complete. Nicely done — take a breather.",
                       "That's one more focused block in the books. Well earned."]
        case (.completed(.work), .punchy):
            options = ["Session complete. No collapse into digital nonsense. Growth.",
                       "Twenty-five minutes of actual work. I'm documenting this for posterity.",
                       "Focus block done. Lowkey impressive. I will deny saying that."]
        case (.completed(.work), .strict):
            options = ["Session complete. Acceptable. Do it again.",
                       "One down. Excellence is a habit, not a single event."]
        case (.completed(.shortBreak), _), (.completed(.longBreak), _):
            options = tone == .polite
                ? ["Break's over whenever you're ready."]
                : ["Break concluded. The mountain did not climb itself in your absence.",
                   "Recess has ended. Hie thee back to thy desk."]
        case (.endedEarly(.work), .polite):
            options = ["Session ended early. That's okay — start another when you can."]
        case (.endedEarly(.work), _):
            options = ["Ended early. Noted. Everything is noted.",
                       "You abandoned the session. It's giving 'commitment issues'."]
        default:
            return nil
        }
        return options[abs(seed) % options.count]
    }
}
