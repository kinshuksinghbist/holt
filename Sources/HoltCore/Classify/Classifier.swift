import Foundation
import GRDB

public enum ActivityCategory: String, Codable, Sendable, CaseIterable {
    case productive, neutral, distracting

    public var title: String {
        switch self {
        case .productive: "Productive"
        case .neutral: "Neutral"
        case .distracting: "Distracting"
        }
    }
}

public enum CategorySource: String, Codable, Sendable {
    case user, `default`, youtube, keyword, screen
}

public enum RuleKind: String, Codable, Sendable, CaseIterable {
    case bundle, domain, urlRegex = "url_regex", titleKeyword = "title_keyword", ytChannel = "yt_channel", ytVideo = "yt_video"

    public var title: String {
        switch self {
        case .bundle: "App Bundle ID"
        case .domain: "Domain"
        case .urlRegex: "URL Regex"
        case .titleKeyword: "Title Keyword"
        case .ytChannel: "YouTube Channel"
        case .ytVideo: "YouTube Video ID"
        }
    }
}

public struct CategoryRuleRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    public static let databaseTableName = "category_rule"

    public var id: Int64?
    public var kind: String
    public var pattern: String
    public var category: String
    public var source: String

    public init(id: Int64? = nil, kind: RuleKind, pattern: String, category: ActivityCategory, source: String = "user") {
        self.id = id
        self.kind = kind.rawValue
        self.pattern = pattern
        self.category = category.rawValue
        self.source = source
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

public struct ClassificationResult: Equatable, Sendable {
    public let category: ActivityCategory
    public let source: CategorySource

    public init(category: ActivityCategory, source: CategorySource) {
        self.category = category
        self.source = source
    }
}

/// Pure, thread-safe classifier matching PLAN §5.4 precedence:
/// user rules → bundled defaults → YouTube category → title keywords → fallback neutral.
public final class Classifier: @unchecked Sendable {
    private let lock = NSLock()
    private let defaultApps: [String: ActivityCategory]
    private let defaultDomains: [String: ActivityCategory]
    private var userRules: [CategoryRuleRecord] = []
    private var cache: [String: ClassificationResult] = [:]

    private static let productiveKeywords = [
        "pull request", "xcode", "documentation", "stack overflow", "commit",
        "localhost", "127.0.0.1", "swagger", "openapi", "rfc ", "tutorial",
        "lecture", "course", "swift", "programming", "debugger", "terminal"
    ]
    private static let distractingKeywords = [
        "official trailer", "reaction", "memes", "tier list", "livestream",
        "highlights", "unboxing", "vlog", "prank", "episode ", "season ",
        "gameplay", "playthrough", "top 10", "top 50", "fails"
    ]

    public init(userRules: [CategoryRuleRecord] = []) {
        self.defaultApps = Self.loadDefaults(name: "defaults_apps")
        self.defaultDomains = Self.loadDefaults(name: "defaults_domains")
        self.userRules = userRules
    }

    public func setUserRules(_ rules: [CategoryRuleRecord]) {
        lock.lock()
        defer { lock.unlock() }
        self.userRules = rules
        self.cache.removeAll()
    }

    public func classifyApp(bundleId: String, appName: String, windowTitle: String? = nil) -> ClassificationResult {
        let key = "app|\(bundleId)|\(windowTitle ?? "")"
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        let rules = userRules
        lock.unlock()

        let res = computeApp(bundleId: bundleId, appName: appName, windowTitle: windowTitle, rules: rules)

        lock.lock()
        cache[key] = res
        lock.unlock()
        return res
    }

    public func classifyWeb(
        domain: String,
        url: String? = nil,
        title: String? = nil,
        ytChannel: String? = nil,
        ytVideoId: String? = nil,
        ytCategory: String? = nil,
        ytPolicy: YouTubePolicy = .categoryBased
    ) -> ClassificationResult {
        let normalizedDomain = Self.normalizeDomain(domain)
        let key = "web|\(normalizedDomain)|\(url ?? "")|\(title ?? "")|\(ytChannel ?? "")|\(ytVideoId ?? "")|\(ytCategory ?? "")|\(ytPolicy.rawValue)"
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        let rules = userRules
        lock.unlock()

        let res = computeWeb(
            domain: normalizedDomain,
            url: url,
            title: title,
            ytChannel: ytChannel,
            ytVideoId: ytVideoId,
            ytCategory: ytCategory,
            ytPolicy: ytPolicy,
            rules: rules
        )

        lock.lock()
        cache[key] = res
        lock.unlock()
        return res
    }

    private func computeApp(
        bundleId: String,
        appName: String,
        windowTitle: String?,
        rules: [CategoryRuleRecord]
    ) -> ClassificationResult {
        let lowerBundle = bundleId.lowercased()
        for rule in rules where rule.kind == RuleKind.bundle.rawValue {
            if rule.pattern.lowercased() == lowerBundle, let cat = ActivityCategory(rawValue: rule.category) {
                return ClassificationResult(category: cat, source: .user)
            }
        }
        if let title = windowTitle?.lowercased() {
            for rule in rules where rule.kind == RuleKind.titleKeyword.rawValue {
                if title.contains(rule.pattern.lowercased()), let cat = ActivityCategory(rawValue: rule.category) {
                    return ClassificationResult(category: cat, source: .user)
                }
            }
        }
        if let cat = defaultApps[bundleId] ?? defaultApps.first(where: { $0.key.lowercased() == lowerBundle })?.value {
            return ClassificationResult(category: cat, source: .default)
        }
        if let title = windowTitle?.lowercased() {
            if Self.productiveKeywords.contains(where: { title.contains($0) }) {
                return ClassificationResult(category: .productive, source: .keyword)
            }
            if Self.distractingKeywords.contains(where: { title.contains($0) }) {
                return ClassificationResult(category: .distracting, source: .keyword)
            }
        }
        if appName.lowercased().contains("terminal") || appName.lowercased().contains("xcode") {
            return ClassificationResult(category: .productive, source: .keyword)
        }
        return ClassificationResult(category: .neutral, source: .default)
    }

    private func computeWeb(
        domain: String,
        url: String?,
        title: String?,
        ytChannel: String?,
        ytVideoId: String?,
        ytCategory: String?,
        ytPolicy: YouTubePolicy,
        rules: [CategoryRuleRecord]
    ) -> ClassificationResult {
        // 1. User rules
        if let vid = ytVideoId?.lowercased() {
            for rule in rules where rule.kind == RuleKind.ytVideo.rawValue {
                if rule.pattern.lowercased() == vid, let cat = ActivityCategory(rawValue: rule.category) {
                    return ClassificationResult(category: cat, source: .user)
                }
            }
        }
        if let ch = ytChannel?.lowercased() {
            for rule in rules where rule.kind == RuleKind.ytChannel.rawValue {
                if rule.pattern.lowercased() == ch, let cat = ActivityCategory(rawValue: rule.category) {
                    return ClassificationResult(category: cat, source: .user)
                }
            }
        }
        if let url {
            for rule in rules where rule.kind == RuleKind.urlRegex.rawValue {
                if let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]),
                   regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil,
                   let cat = ActivityCategory(rawValue: rule.category) {
                    return ClassificationResult(category: cat, source: .user)
                }
            }
        }
        for rule in rules where rule.kind == RuleKind.domain.rawValue {
            let p = Self.normalizeDomain(rule.pattern)
            if domain == p || domain.hasSuffix(".\(p)"), let cat = ActivityCategory(rawValue: rule.category) {
                return ClassificationResult(category: cat, source: .user)
            }
        }
        if let titleLower = title?.lowercased() {
            for rule in rules where rule.kind == RuleKind.titleKeyword.rawValue {
                if titleLower.contains(rule.pattern.lowercased()), let cat = ActivityCategory(rawValue: rule.category) {
                    return ClassificationResult(category: cat, source: .user)
                }
            }
        }

        // 2. YouTube specific policy & category map
        let isYouTube = domain == "youtube.com" || domain.hasSuffix(".youtube.com") || domain == "youtu.be"
        if isYouTube {
            switch ytPolicy {
            case .alwaysDistracting:
                return ClassificationResult(category: .distracting, source: .youtube)
            case .categoryBased, .educationalAllowed:
                if let ytCategory {
                    let mapped = Self.classifyYouTubeCategory(ytCategory, educationalAllowed: ytPolicy == .educationalAllowed)
                    return ClassificationResult(category: mapped, source: .youtube)
                }
                // Check title keywords before defaulting YouTube to distracting
                if let titleLower = title?.lowercased() {
                    if Self.productiveKeywords.contains(where: { titleLower.contains($0) }) {
                        return ClassificationResult(category: .productive, source: .keyword)
                    }
                }
                return ClassificationResult(category: .distracting, source: .default)
            }
        }

        // 3. Bundled domain defaults (exact or parent domain)
        if let direct = defaultDomains[domain] {
            return ClassificationResult(category: direct, source: .default)
        }
        let parts = domain.split(separator: ".")
        if parts.count > 2 {
            let parent = parts.suffix(2).joined(separator: ".")
            if let parentCat = defaultDomains[parent] {
                return ClassificationResult(category: parentCat, source: .default)
            }
        }

        // 4. Title keywords
        if let titleLower = title?.lowercased() {
            if Self.productiveKeywords.contains(where: { titleLower.contains($0) }) {
                return ClassificationResult(category: .productive, source: .keyword)
            }
            if Self.distractingKeywords.contains(where: { titleLower.contains($0) }) {
                return ClassificationResult(category: .distracting, source: .keyword)
            }
        }

        return ClassificationResult(category: .neutral, source: .default)
    }

    public static func classifyYouTubeCategory(_ raw: String, educationalAllowed: Bool) -> ActivityCategory {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch lower {
        case "education", "science & technology", "howto & style":
            return educationalAllowed ? .productive : .neutral
        case "news & politics", "nonprofits & activism":
            return .neutral
        case "entertainment", "comedy", "gaming", "music", "people & blogs",
             "sports", "film & animation", "autos & vehicles", "pets & animals",
             "travel & events", "shows", "movies", "trailers":
            return .distracting
        default:
            return .neutral
        }
    }

    private static func normalizeDomain(_ raw: String) -> String {
        let d = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return d.hasPrefix("www.") ? String(d.dropFirst(4)) : d
    }

    private static func loadDefaults(name: String) -> [String: ActivityCategory] {
        guard let url = HoltCoreResources.bundle.url(forResource: name, withExtension: "json", subdirectory: "Classify")
            ?? HoltCoreResources.bundle.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        var out: [String: ActivityCategory] = [:]
        for (k, v) in raw {
            if let cat = ActivityCategory(rawValue: v) {
                out[k] = cat
            }
        }
        return out
    }
}
