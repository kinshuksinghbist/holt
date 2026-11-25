import Foundation
import Testing
@testable import HoltCore

@Suite("ScreenLabeler & Exclusions")
struct ScreenLabelerTests {
    @Test func labelsOCRTextFixturesAccurately() {
        struct Fixture {
            let ocr: String
            let bundleId: String?
            let appName: String?
            let title: String?
            let task: String?
            let expectedLabel: ScreenActivityLabel
            let expectedOnTask: OnTaskStatus?
        }

        let fixtures: [Fixture] = [
            Fixture(
                ocr: "import SwiftUI\nstruct ContentView: View {\n  func body() -> some View {\n    return Text(\"Hello\")\n  }\n}\nBuild Succeeded",
                bundleId: "com.apple.dt.Xcode", appName: "Xcode", title: "App.swift", task: "Build UI",
                expectedLabel: .code, expectedOnTask: .yes
            ),
            Fixture(
                ocr: "git status\ngit commit -m \"fix\"\nlocalhost:8080\nerror: missing semicolon\nstack trace",
                bundleId: "com.googlecode.iterm2", appName: "iTerm2", title: "zsh", task: "Fix backend",
                expectedLabel: .code, expectedOnTask: .yes
            ),
            Fixture(
                ocr: "Product Specification\nTable of Contents\nSection 1: Requirements\nArchitecture Draft\nMeeting notes for Q4 proposal",
                bundleId: "notion.id", appName: "Notion", title: "Q4 Proposal", task: "Write proposal",
                expectedLabel: .docs, expectedOnTask: .yes
            ),
            Fixture(
                ocr: "Inbox (12 unread)\nFrom: alice@example.com\nSubject: Contract review\nReply  Reply All  Forward  Attachments",
                bundleId: "com.apple.mail", appName: "Mail", title: "Inbox", task: "Ship code",
                expectedLabel: .email, expectedOnTask: .unclear
            ),
            Fixture(
                ocr: "Channels\n#general\n#engineering\nDirect Messages\nAlice is typing...\nSend a message to #engineering",
                bundleId: "com.tinyspeck.slackmacgap", appName: "Slack", title: "Slack", task: "Debug CI",
                expectedLabel: .chat, expectedOnTask: .unclear
            ),
            Fixture(
                ocr: "YouTube\nSubscribe  1.2M subscribers\nUp Next  Autoplay\nWatch Later  Comments (432)\nTop 50 Funny Fails",
                bundleId: "com.google.Chrome", appName: "Google Chrome", title: "Top 50 Funny Fails", task: "Write proposal",
                expectedLabel: .video, expectedOnTask: .no
            ),
            Fixture(
                ocr: "YouTube\nSubscribe  Watch Later  Autoplay\nSwift Concurrency Sendable Tutorial\nCaptions  Playback speed",
                bundleId: "com.google.Chrome", appName: "Google Chrome", title: "Swift Concurrency", task: "Learn Swift Concurrency",
                expectedLabel: .video, expectedOnTask: .yes
            ),
            Fixture(
                ocr: "Amazon.com\nFree shipping on orders over $35\nIn Stock\nAdd to Cart\nBuy Now\nCustomer reviews 4.7",
                bundleId: "com.apple.Safari", appName: "Safari", title: "Mechanical Keyboard", task: "Write tests",
                expectedLabel: .shopping, expectedOnTask: .no
            ),
            Fixture(
                ocr: "For You   Following\nTrending in Technology\n2.4K Likes   412 Repost\nWhat's happening\nr/AskReddit  Upvote",
                bundleId: "com.apple.Safari", appName: "Safari", title: "Home Feed", task: "Write tests",
                expectedLabel: .socialFeed, expectedOnTask: .no
            ),
            Fixture(
                ocr: "Steam\nMatchmaking\nLeaderboard  FPS: 144\nHealth Bar  Inventory  Quest Complete\nAchievement Unlocked",
                bundleId: "com.valvesoftware.steam", appName: "Steam", title: "Game", task: "Write tests",
                expectedLabel: .game, expectedOnTask: .no
            ),
            Fixture(
                ocr: "Figma\nLayers   Artboard 1   Auto Layout\nStroke  Fill  Opacity 100%\nComponents  Prototype  Export PNG",
                bundleId: "com.figma.Desktop", appName: "Figma", title: "Dashboard.fig", task: "Design dashboard",
                expectedLabel: .design, expectedOnTask: .yes
            ),
        ]

        var hits = 0
        for f in fixtures {
            let res = ScreenLabeler.label(
                ocrText: f.ocr,
                bundleId: f.bundleId,
                appName: f.appName,
                windowTitle: f.title,
                activeTaskTitle: f.task
            )
            if res.label == f.expectedLabel && (f.expectedOnTask == nil || res.onTask == f.expectedOnTask) {
                hits += 1
            }
        }
        let accuracy = Double(hits) / Double(fixtures.count)
        #expect(accuracy >= 0.8)
    }

    @Test func exclusionsBlockPasswordManagersBankingPrivateAndCustom() {
        #expect(ScreenExclusions.shouldSkip(
            bundleId: "com.1password.1password", appName: "1Password", windowTitle: "Vault", url: nil, userExclusions: []
        ))
        #expect(ScreenExclusions.shouldSkip(
            bundleId: "com.apple.keychainaccess", appName: "Keychain Access", windowTitle: nil, url: nil, userExclusions: []
        ))
        #expect(ScreenExclusions.shouldSkip(
            bundleId: "com.apple.Safari", appName: "Safari", windowTitle: "Private Browsing", url: nil, userExclusions: []
        ))
        #expect(ScreenExclusions.shouldSkip(
            bundleId: "com.google.Chrome", appName: "Chrome", windowTitle: "Checking Account", url: "https://www.chase.com/account", userExclusions: []
        ))
        #expect(ScreenExclusions.shouldSkip(
            bundleId: "com.example.secret", appName: "SecretApp", windowTitle: "Medical Chart", url: nil, userExclusions: ["medical"]
        ))
        #expect(!ScreenExclusions.shouldSkip(
            bundleId: "com.apple.dt.Xcode", appName: "Xcode", windowTitle: "Holt.swift", url: nil, userExclusions: ["medical"]
        ))
    }

    @Test func screenStorePersistsObservations() throws {
        let db = try HoltDatabase.openInMemory()
        let store = ScreenStore(db: db)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try store.record(ScreenObservationRecord(
            ts: Int64(now.timeIntervalSince1970),
            sessionId: nil,
            bundleId: "com.apple.dt.Xcode",
            label: "code",
            onTask: "yes",
            confidence: 0.91,
            keywords: "swift,func,struct"
        ))
        let obs = try store.fetchObservations(day: HoltDay.key(for: now))
        #expect(obs.count == 1)
        #expect(obs[0].label == "code")
    }
}
