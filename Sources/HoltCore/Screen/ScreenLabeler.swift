import Foundation
import GRDB

public enum ScreenActivityLabel: String, Codable, Sendable, CaseIterable {
    case code, docs, email, chat, video, shopping, socialFeed = "social feed", game, design, other

    public var isOffTaskCategory: Bool {
        switch self {
        case .shopping, .socialFeed, .game: true
        default: false
        }
    }
}

public enum OnTaskStatus: String, Codable, Sendable {
    case yes, no, unclear
}

public struct ScreenLabelResult: Equatable, Sendable {
    public let label: ScreenActivityLabel
    public let onTask: OnTaskStatus
    public let confidence: Double
    public let keywords: [String]

    public init(label: ScreenActivityLabel, onTask: OnTaskStatus, confidence: Double, keywords: [String]) {
        self.label = label
        self.onTask = onTask
        self.confidence = confidence
        self.keywords = keywords
    }
}

public struct ScreenObservationRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "screen_observation"

    public var id: Int64?
    public var ts: Int64
    public var sessionId: Int64?
    public var bundleId: String?
    public var label: String?
    public var onTask: String?
    public var confidence: Double?
    public var keywords: String?

    public enum CodingKeys: String, CodingKey {
        case id, ts, label, confidence, keywords
        case sessionId = "session_id"
        case bundleId = "bundle_id"
        case onTask = "on_task"
    }

    public init(
        id: Int64? = nil,
        ts: Int64,
        sessionId: Int64? = nil,
        bundleId: String? = nil,
        label: String? = nil,
        onTask: String? = nil,
        confidence: Double? = nil,
        keywords: String? = nil
    ) {
        self.id = id
        self.ts = ts
        self.sessionId = sessionId
        self.bundleId = bundleId
        self.label = label
        self.onTask = onTask
        self.confidence = confidence
        self.keywords = keywords
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct ScreenStore: Sendable {
    public let db: HoltDatabase

    public init(db: HoltDatabase) {
        self.db = db
    }

    @discardableResult
    public func record(_ obs: ScreenObservationRecord) throws -> ScreenObservationRecord {
        try db.writer.write { db in
            var copy = obs
            try copy.insert(db)
            return copy
        }
    }

    public func fetchObservations(day: String, rolloverHour: Int = 4, calendar: Calendar = .current) throws -> [ScreenObservationRecord] {
        guard let bounds = HoltDay.bounds(forKey: day, rolloverHour: rolloverHour, calendar: calendar) else { return [] }
        return try db.writer.read { db in
            try ScreenObservationRecord.fetchAll(
                db,
                sql: "SELECT * FROM screen_observation WHERE ts >= ? AND ts < ? ORDER BY ts DESC",
                arguments: [bounds.start, bounds.end]
            )
        }
    }
}

public enum ScreenExclusions {
    private static let excludedBundleIds: Set<String> = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.lastpass.LastPass",
        "com.dashlane.Dashlane",
        "org.keepassxc.keepassxc",
        "com.apple.keychainaccess",
        "com.apple.Passwords",
        "com.apple.systempreferences",
    ]

    private static let excludedTitleSubstrings: [String] = [
        "private browsing",
        "inprivate",
        "incognito",
        "1password",
        "bitwarden",
        "keychain access",
        "online banking",
        "bank of america",
        "wells fargo",
        "chase.com",
        "citibank",
        "american express",
        "capital one",
        "charles schwab",
        "fidelity",
        "vanguard",
        "mercury.com",
        "paypal",
    ]

    public static func shouldSkip(
        bundleId: String,
        appName: String,
        windowTitle: String?,
        url: String?,
        userExclusions: [String]
    ) -> Bool {
        let lowerBundle = bundleId.lowercased()
        if excludedBundleIds.contains(where: { $0.lowercased() == lowerBundle }) {
            return true
        }
        let haystack = [bundleId, appName, windowTitle ?? "", url ?? ""].joined(separator: " ").lowercased()
        if excludedTitleSubstrings.contains(where: { haystack.contains($0) }) {
            return true
        }
        for custom in userExclusions {
            let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !trimmed.isEmpty && haystack.contains(trimmed) {
                return true
            }
        }
        return false
    }
}

/// Pure, rule-based on-device classifier over Apple Vision OCR text + app prior + task overlap.
public enum ScreenLabeler {
    private static let keywordWeights: [(label: ScreenActivityLabel, keywords: [(String, Double)])] = [
        (.code, [
            ("func ", 2.0), ("struct ", 2.0), ("class ", 1.5), ("import ", 1.5),
            ("public ", 1.2), ("return ", 1.2), ("async ", 1.3), ("throws", 1.3),
            ("pull request", 2.0), ("commit", 1.5), ("branch", 1.2), ("merge", 1.2),
            ("xcode", 2.0), ("terminal", 1.6), ("swift", 1.6), ("python", 1.6),
            ("typescript", 1.6), ("localhost", 1.5), ("debugger", 1.6), ("breakpoint", 1.6),
            ("error:", 1.4), ("warning:", 1.2), ("stack trace", 1.8), ("git ", 1.5),
            ("=>", 1.2), ("->", 1.2), ("{", 0.5), ("}", 0.5),
        ]),
        (.docs, [
            ("documentation", 2.0), ("specification", 2.0), ("readme", 1.8),
            ("table of contents", 1.8), ("chapter", 1.4), ("section", 1.0),
            ("proposal", 1.6), ("architecture", 1.6), ("meeting notes", 1.8),
            ("summary", 1.3), ("google docs", 2.0), ("notion", 1.6),
            ("markdown", 1.5), ("appendix", 1.5), ("requirements", 1.5),
            ("draft", 1.2), ("abstract", 1.4), ("references", 1.2),
        ]),
        (.email, [
            ("inbox", 2.2), ("compose", 1.8), ("reply", 1.6), ("reply all", 2.0),
            ("forward", 1.5), ("subject:", 2.0), ("from:", 1.5), ("to:", 1.2),
            ("cc:", 1.8), ("unread", 1.5), ("sent mail", 2.0), ("drafts", 1.4),
            ("attachments", 1.5), ("archive", 1.2), ("gmail", 2.0), ("outlook", 1.8),
        ]),
        (.chat, [
            ("direct messages", 2.2), ("channels", 1.8), ("#general", 2.0),
            ("typing...", 2.0), ("thread", 1.5), ("slack", 2.2), ("discord", 2.2),
            ("huddle", 1.8), ("unread messages", 2.0), ("send a message", 1.8),
            ("online", 0.8), ("reactions", 1.3), ("@channel", 2.0), ("@here", 2.0),
        ]),
        (.video, [
            ("subscribe", 2.2), ("subscribers", 2.0), ("watch later", 2.2),
            ("up next", 2.0), ("autoplay", 2.0), ("views", 1.5),
            ("youtube", 2.2), ("comments", 1.3), ("share", 0.8), ("playback", 1.6),
            ("captions", 1.4), ("fullscreen", 1.3), ("playlist", 1.7),
        ]),
        (.shopping, [
            ("add to cart", 2.5), ("proceed to checkout", 2.5), ("checkout", 2.0),
            ("buy now", 2.4), ("shopping cart", 2.5), ("free shipping", 2.2),
            ("in stock", 1.8), ("wishlist", 1.8), ("order total", 2.2),
            ("customer reviews", 1.8), ("delivery", 1.3), ("price", 1.0),
            ("add to bag", 2.4), ("amazon", 1.6),
        ]),
        (.socialFeed, [
            ("for you", 1.8), ("following", 1.5), ("repost", 2.4), ("retweet", 2.4),
            ("subreddit", 2.5), ("upvote", 2.5), ("r/", 1.6), ("trending", 1.6),
            ("what's happening", 2.2), ("post", 0.8), ("likes", 1.2), ("followers", 1.8),
            ("explore", 1.0), ("feed", 1.3), ("reddit", 2.2), ("instagram", 2.2),
        ]),
        (.game, [
            ("respawn", 2.5), ("leaderboard", 2.0), ("matchmaking", 2.5),
            ("inventory", 1.8), ("fps", 1.6), ("quest", 1.8), ("achievement", 2.0),
            ("multiplayer", 2.2), ("singleplayer", 2.2), ("steam", 2.0),
            ("play now", 1.8), ("level up", 1.8), ("health bar", 2.0),
        ]),
        (.design, [
            ("figma", 2.4), ("layers", 2.0), ("artboard", 2.2), ("stroke", 1.8),
            ("fill", 1.4), ("opacity", 1.6), ("prototype", 1.8), ("constraints", 1.8),
            ("auto layout", 2.2), ("components", 1.6), ("export", 1.2), ("vector", 1.8),
        ]),
    ]

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "from", "that", "this", "into", "your", "have", "make", "work", "task"
    ]

    public static func label(
        ocrText: String,
        bundleId: String?,
        appName: String?,
        windowTitle: String?,
        activeTaskTitle: String?
    ) -> ScreenLabelResult {
        let normalized = [ocrText, windowTitle ?? ""].joined(separator: "\n").lowercased()
        var scores: [ScreenActivityLabel: Double] = [:]
        var matchedKeywords: [ScreenActivityLabel: [String]] = [:]

        for (lbl, kws) in keywordWeights {
            for (kw, weight) in kws where normalized.contains(kw) {
                scores[lbl, default: 0] += weight
                matchedKeywords[lbl, default: []].append(kw.trimmingCharacters(in: .whitespaces))
            }
        }

        // App prior
        let appContext = [bundleId ?? "", appName ?? ""].joined(separator: " ").lowercased()
        if appContext.contains("xcode") || appContext.contains("vscode") || appContext.contains("cursor")
            || appContext.contains("terminal") || appContext.contains("iterm") || appContext.contains("ghostty")
            || appContext.contains("zed") {
            scores[.code, default: 0] += 2.2
        } else if appContext.contains("mail") || appContext.contains("spark") || appContext.contains("mimestream") {
            scores[.email, default: 0] += 2.2
        } else if appContext.contains("slack") || appContext.contains("discord") || appContext.contains("messages") {
            scores[.chat, default: 0] += 2.2
        } else if appContext.contains("figma") || appContext.contains("sketch") || appContext.contains("photoshop") {
            scores[.design, default: 0] += 2.2
        } else if appContext.contains("notes") || appContext.contains("notion") || appContext.contains("obsidian") || appContext.contains("pages") {
            scores[.docs, default: 0] += 1.8
        } else if appContext.contains("steam") {
            scores[.game, default: 0] += 2.5
        }

        let sorted = scores.sorted { $0.value > $1.value }
        let top = sorted.first
        let second = sorted.dropFirst().first

        let chosenLabel: ScreenActivityLabel
        let confidence: Double
        if let top, top.value >= 1.5 {
            chosenLabel = top.key
            let runnerUp = second?.value ?? 0
            let margin = (top.value - runnerUp) / max(top.value, 1.0)
            confidence = min(0.98, max(0.35, 0.45 + 0.35 * margin + min(0.2, top.value / 15.0)))
        } else {
            chosenLabel = .other
            confidence = 0.25
        }

        let taskOverlap = computeTaskOverlap(taskTitle: activeTaskTitle, text: normalized)
        let onTask: OnTaskStatus
        if chosenLabel.isOffTaskCategory {
            onTask = .no
        } else if chosenLabel == .video {
            onTask = taskOverlap >= 1 ? .yes : .no
        } else if taskOverlap >= 1 || chosenLabel == .code || chosenLabel == .docs || chosenLabel == .design {
            onTask = .yes
        } else if chosenLabel == .email || chosenLabel == .chat {
            onTask = .unclear
        } else {
            onTask = .unclear
        }

        let digest = Array((matchedKeywords[chosenLabel] ?? []).prefix(6))
        return ScreenLabelResult(
            label: chosenLabel,
            onTask: onTask,
            confidence: (confidence * 100).rounded() / 100,
            keywords: digest
        )
    }

    private static func computeTaskOverlap(taskTitle: String?, text: String) -> Int {
        guard let taskTitle else { return 0 }
        let tokens = taskTitle
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
        return tokens.filter { text.contains($0) }.count
    }
}
