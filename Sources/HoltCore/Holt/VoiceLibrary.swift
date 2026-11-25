import Foundation

public enum VoiceTrigger: String, Codable, Sendable, CaseIterable {
    case sessionStart = "session_start"
    case sessionComplete = "session_complete"
    case sessionAbandon = "session_abandon"
    case breakOver = "break_over"
    case idlePause = "idle_pause"
    case workingTooLong = "working_too_long"
    case distraction = "distraction"
    case ytEntertainment = "yt_entertainment"
    case noSessionActive = "no_session_active"
    case hourlyReminder = "hourly_reminder"
    case morningBrief = "morning_brief"
    case eodSummary = "eod_summary"
    case weeklyReview = "weekly_review"
    case streak = "streak"
    case comeback = "comeback"
    case taskDone = "task_done"
    case taskSkipped = "task_skipped"
    case rollover = "rollover"
}

public enum VoiceStyle: String, Codable, Sendable {
    case standard, archaic, genz
}

public struct VoiceTemplate: Codable, Equatable, Sendable {
    public let id: String
    public let trigger: VoiceTrigger
    public let tone: ToneBand
    public let requires: [String]
    public let style: VoiceStyle
    public let profanity: Bool
    public let text: String
}

public struct RenderedVoiceLine: Equatable, Sendable {
    public let templateId: String
    public let text: String
}

/// Template voice library loaded from `Resources/voice/*.json`.
public final class VoiceLibrary: @unchecked Sendable {
    public static let shared = VoiceLibrary()

    public static let supportedSlots: Set<String> = [
        "task", "count", "site", "app", "video", "minutes", "hours",
        "streak", "score", "days", "skips", "left", "done", "planned",
        "yesterday_left", "best_hour", "distract"
    ]

    public static let bannedPhrases: [String] = [
        "Great job", "I understand", "delve", "journey", "!!",
        "Let's", "Remember,", "As an AI", "it's important to"
    ]

    public let templates: [VoiceTemplate]

    public init(templates: [VoiceTemplate]? = nil) {
        self.templates = templates ?? Self.loadBundledTemplates()
    }

    public func templates(for trigger: VoiceTrigger, tone: ToneBand) -> [VoiceTemplate] {
        templates.filter { $0.trigger == trigger && $0.tone == tone }
    }

    public func render(
        trigger: VoiceTrigger,
        tone: ToneBand,
        facts: FactSheet,
        overrides: [String: String] = [:],
        slangMix: Double = 0.5,
        allowProfanity: Bool = false,
        seed: Int = 0
    ) -> RenderedVoiceLine? {
        let slots = Self.slotValues(from: facts, overrides: overrides)
        let pool = templates(for: trigger, tone: tone).filter { tpl in
            (allowProfanity || !tpl.profanity) &&
            tpl.requires.allSatisfy { req in
                guard let val = slots[req], !val.isEmpty else { return false }
                switch req {
                case "streak": return (Int(val) ?? 0) >= 2
                case "skips": return (Int(val) ?? 0) >= 2
                case "days": return (Int(val) ?? 0) >= 2
                case "yesterday_left": return (Int(val) ?? 0) >= 1
                default: return true
                }
            }
        }

        let candidates: [VoiceTemplate]
        if pool.isEmpty {
            // Fallback to lines without unmet specific preconditions (using always-available counts/minutes).
            candidates = templates(for: trigger, tone: tone).filter { allowProfanity || !$0.profanity }
        } else {
            candidates = pool
        }
        guard !candidates.isEmpty else { return nil }

        let recentSet = Set(facts.recentTemplateIds)
        let fresh = candidates.filter { !recentSet.contains($0.id) }
        let preferredPool = fresh.isEmpty ? candidates : fresh

        let desiredStyle: VoiceStyle
        if slangMix < 0.34 {
            desiredStyle = .archaic
        } else if slangMix > 0.66 {
            desiredStyle = .genz
        } else {
            desiredStyle = .standard
        }
        let styleFiltered = preferredPool.filter { $0.style == desiredStyle || $0.style == .standard }
        let finalPool = styleFiltered.isEmpty ? preferredPool : styleFiltered

        let chosen = finalPool[Int(UInt(bitPattern: seed) % UInt(finalPool.count))]
        let filled = Self.fill(template: chosen.text, slots: slots)
        return RenderedVoiceLine(templateId: chosen.id, text: filled)
    }

    public static func fill(template: String, slots: [String: String], maxLength: Int = 140) -> String {
        var result = template
        for (key, rawVal) in slots {
            let safeVal = rawVal.count > 36 ? String(rawVal.prefix(33)) + "..." : rawVal
            result = result.replacingOccurrences(of: "{\(key)}", with: safeVal)
        }
        // Replace any unfilled optional slot gracefully
        for key in supportedSlots {
            result = result.replacingOccurrences(of: "{\(key)}", with: "0")
        }
        if result.count <= maxLength { return result }
        return String(result.prefix(maxLength - 3)) + "..."
    }

    public static func slotValues(from facts: FactSheet, overrides: [String: String] = [:]) -> [String: String] {
        var map: [String: String] = [
            "left": String(facts.today.leftCount),
            "done": String(facts.today.doneCount),
            "planned": String(facts.today.plannedCount),
            "minutes": String(max(0, facts.today.focusMinutes)),
            "distract": String(max(0, facts.today.distractMinutes)),
            "count": String(max(1, facts.today.sessionsDone)),
            "score": String(facts.today.focusScore),
            "yesterday_left": String(facts.yesterday.unfinishedCount),
            "streak": String(facts.recent.streakDays),
            "days": String(facts.recent.longestRolloverDays),
            "skips": String(facts.recent.mostSkippedCount),
            "hours": String(facts.recent.weeklyFocusHours),
        ]
        if let task = facts.today.currentTaskTitle ?? facts.today.doingTitle ?? facts.today.topTodoTitle ?? facts.recent.mostSkippedTitle {
            map["task"] = task
        }
        if let site = facts.today.currentSite ?? facts.today.topDistraction {
            map["site"] = site
        }
        if let app = facts.today.currentApp {
            map["app"] = app
        }
        if let video = facts.today.currentVideoTitle {
            map["video"] = video
        }
        if let best = facts.recent.bestHour {
            map["best_hour"] = best
        }
        for (k, v) in overrides {
            map[k] = v
        }
        return map
    }

    private static func loadBundledTemplates() -> [VoiceTemplate] {
        let names = ["session", "nudges", "summaries", "tasks"]
        var all: [VoiceTemplate] = []
        let decoder = JSONDecoder()
        for name in names {
            guard let url = HoltCoreResources.bundle.url(forResource: name, withExtension: "json", subdirectory: "voice")
                ?? HoltCoreResources.bundle.url(forResource: name, withExtension: "json"),
                  let data = try? Data(contentsOf: url),
                  let items = try? decoder.decode([VoiceTemplate].self, from: data) else {
                continue
            }
            all.append(contentsOf: items)
        }
        return all
    }
}
