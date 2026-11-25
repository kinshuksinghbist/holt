import Foundation
import Testing
@testable import HoltCore

@Suite("Classifier & Procrastination")
struct ClassifierAndTrackingTests {
    @Test func bundledDefaultsClassifyCommonAppsAndDomains() {
        let c = Classifier()
        #expect(c.classifyApp(bundleId: "com.apple.dt.Xcode", appName: "Xcode").category == .productive)
        #expect(c.classifyApp(bundleId: "com.hnc.Discord", appName: "Discord").category == .distracting)
        #expect(c.classifyWeb(domain: "github.com").category == .productive)
        #expect(c.classifyWeb(domain: "sub.reddit.com").category == .distracting)
    }

    @Test func userRulesOverrideDefaultsAndYouTubePolicyApplies() {
        let rule = CategoryRuleRecord(kind: .ytChannel, pattern: "3Blue1Brown", category: .productive)
        let c = Classifier(userRules: [rule])

        // User rule wins for channel
        let math = c.classifyWeb(
            domain: "youtube.com",
            title: "Linear algebra",
            ytChannel: "3Blue1Brown",
            ytCategory: "Education",
            ytPolicy: .alwaysDistracting
        )
        #expect(math.category == .productive)
        #expect(math.source == .user)

        // YouTube entertainment is distracting under categoryBased
        let ent = c.classifyWeb(
            domain: "youtube.com",
            title: "Top 50 Fails",
            ytChannel: "RandomChannel",
            ytCategory: "Entertainment",
            ytPolicy: .categoryBased
        )
        #expect(ent.category == .distracting)
        #expect(ent.source == .youtube)

        // Educational allowed under educationalAllowed
        let edu = c.classifyWeb(
            domain: "youtube.com",
            title: "Swift Concurrency Deep Dive",
            ytChannel: "SomeUni",
            ytCategory: "Science & Technology",
            ytPolicy: .educationalAllowed
        )
        #expect(edu.category == .productive)
        #expect(edu.source == .youtube)
    }

    @Test func spanStoreReclassifiesAndPrunes() throws {
        let db = try HoltDatabase.openInMemory()
        let store = SpanStore(db: db)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let day = HoltDay.key(for: t0)

        let web = WebSpanRecord(
            browser: "Safari",
            url: "https://reddit.com/r/swift",
            domain: "reddit.com",
            title: "Swift tips",
            startedAt: Int64(t0.timeIntervalSince1970),
            endedAt: Int64(t0.timeIntervalSince1970) + 120,
            category: ActivityCategory.distracting.rawValue,
            categorySource: CategorySource.default.rawValue
        )
        try store.writeBatch(appSpans: [], webSpans: [web])
        _ = try store.upsertUserRule(kind: .domain, pattern: "reddit.com", category: .productive)
        try store.reclassifyMatching(kind: .domain, pattern: "reddit.com", to: .productive)

        let fetched = try store.fetchWebSpans(day: day)
        #expect(fetched.count == 1)
        #expect(fetched[0].category == ActivityCategory.productive.rawValue)
        #expect(fetched[0].categorySource == CategorySource.user.rawValue)

        try store.pruneOldRawSpans(olderThanDays: 1, now: t0.addingTimeInterval(3 * 86400))
        #expect(try store.fetchWebSpans(day: day).isEmpty)
    }

    @Test func procrastinationDetectorEscalatesAndDetectsRapidSwitching() {
        var d = ProcrastinationDetector()
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)

        // At 0s: no alert
        let a0 = d.evaluate(
            now: t0, inWorkSession: true, isIdle: false, hasUndoneTodos: true,
            subjectName: "reddit.com", subjectKey: "web:reddit.com",
            ruleKind: .domain, rulePattern: "reddit.com",
            category: .distracting, isYouTubeEntertainment: false
        )
        #expect(a0.isEmpty)

        // At 65s: severity 1
        let a1 = d.evaluate(
            now: t0.addingTimeInterval(65), inWorkSession: true, isIdle: false, hasUndoneTodos: true,
            subjectName: "reddit.com", subjectKey: "web:reddit.com",
            ruleKind: .domain, rulePattern: "reddit.com",
            category: .distracting, isYouTubeEntertainment: false
        )
        #expect(a1.count == 1)
        #expect(a1[0].severity == 1)
        #expect(a1[0].kind == .distractingSite)

        // At 190s: severity 2
        let a2 = d.evaluate(
            now: t0.addingTimeInterval(190), inWorkSession: true, isIdle: false, hasUndoneTodos: true,
            subjectName: "reddit.com", subjectKey: "web:reddit.com",
            ruleKind: .domain, rulePattern: "reddit.com",
            category: .distracting, isYouTubeEntertainment: false
        )
        #expect(a2.count == 1)
        #expect(a2[0].severity == 2)

        // Rapid switching (> 12 in 5 min)
        for i in 0..<14 {
            d.recordAppSwitch(bundleId: "app.\(i % 4)", now: t0.addingTimeInterval(200 + Double(i)))
        }
        let a3 = d.evaluate(
            now: t0.addingTimeInterval(220), inWorkSession: true, isIdle: false, hasUndoneTodos: true,
            subjectName: "Xcode", subjectKey: "app:com.apple.dt.Xcode",
            ruleKind: .bundle, rulePattern: "com.apple.dt.Xcode",
            category: .productive, isYouTubeEntertainment: false
        )
        #expect(a3.contains { $0.kind == .rapidSwitching })
    }

    @Test func youtubeVideoIdExtraction() {
        #expect(BrowserTabEvent.extractYouTubeVideoId(from: "https://www.youtube.com/watch?v=dQw4w9WgXcQ") == "dQw4w9WgXcQ")
        #expect(BrowserTabEvent.extractYouTubeVideoId(from: "https://youtu.be/abc123") == "abc123")
        #expect(BrowserTabEvent.extractYouTubeVideoId(from: "https://www.youtube.com/shorts/xyz789") == "xyz789")
        #expect(BrowserTabEvent.extractDomain(from: "https://www.GitHub.com/org/repo") == "github.com")
    }
}
