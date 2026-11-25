import AppKit
import Foundation
import HoltCore

struct BrowserTabSample: Equatable, Sendable {
    let browser: String
    let url: String?
    let domain: String
    let title: String?
    let incognito: Bool
    let ytVideoId: String?
    let ytChannel: String?
    let ytCategory: String?
}

/// Runs precompiled `NSAppleScript` queries off the main actor.
actor AppleScriptBrowserReader {
    private var compiledScripts: [String: NSAppleScript] = [:]

    func readActiveTab(bundleId: String) -> BrowserTabSample? {
        guard let spec = Self.browserSpec(for: bundleId) else { return nil }
        let script: NSAppleScript
        if let existing = compiledScripts[bundleId] {
            script = existing
        } else {
            guard let created = NSAppleScript(source: spec.source) else { return nil }
            created.compileAndReturnError(nil)
            compiledScripts[bundleId] = created
            script = created
        }

        var errorDict: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorDict)
        if errorDict != nil { return nil }
        guard descriptor.numberOfItems >= 2 else { return nil }
        let url = descriptor.atIndex(1)?.stringValue ?? ""
        let title = descriptor.atIndex(2)?.stringValue ?? ""
        let mode = descriptor.numberOfItems >= 3 ? (descriptor.atIndex(3)?.stringValue ?? "") : ""
        if mode == "incognito" || url.isEmpty { return nil }
        guard let domain = BrowserTabEvent.extractDomain(from: url) else { return nil }

        return BrowserTabSample(
            browser: spec.name,
            url: url,
            domain: domain,
            title: title.isEmpty ? nil : title,
            incognito: false,
            ytVideoId: BrowserTabEvent.extractYouTubeVideoId(from: url),
            ytChannel: nil,
            ytCategory: nil
        )
    }

    private static func browserSpec(for bundleId: String) -> (name: String, source: String)? {
        switch bundleId {
        case "com.apple.Safari":
            return ("Safari", """
                tell application "Safari"
                    if (count of windows) > 0 then
                        try
                            set t to current tab of front window
                            return {URL of t, name of t, "normal"}
                        on error
                            return {"", "", "incognito"}
                        end try
                    end if
                end tell
                return {"", "", ""}
                """)
        case "com.google.Chrome":
            return ("Chrome", chromiumScript(appName: "Google Chrome"))
        case "com.brave.Browser":
            return ("Brave", chromiumScript(appName: "Brave Browser"))
        case "com.microsoft.edgemac":
            return ("Edge", chromiumScript(appName: "Microsoft Edge"))
        case "com.vivaldi.Vivaldi":
            return ("Vivaldi", chromiumScript(appName: "Vivaldi"))
        case "company.thebrowser.Browser":
            return ("Arc", """
                tell application "Arc"
                    if (count of windows) > 0 then
                        try
                            set t to active tab of front window
                            return {URL of t, title of t, "normal"}
                        on error
                            return {"", "", "incognito"}
                        end try
                    end if
                end tell
                return {"", "", ""}
                """)
        default:
            return nil
        }
    }

    private static func chromiumScript(appName: String) -> String {
        """
        tell application "\(appName)"
            if (count of windows) > 0 then
                try
                    set w to front window
                    set m to mode of w
                    if m is "incognito" then return {"", "", "incognito"}
                    set t to active tab of w
                    return {URL of t, title of t, m}
                on error
                    return {"", "", ""}
                end try
            end if
        end tell
        return {"", "", ""}
        """
    }
}

/// Tracks active browser tabs via Apple Events (Safari/Chromium) + Native Messaging extension (Firefox + rich YouTube data).
@MainActor
final class BrowserTracker {
    struct CurrentWeb: Equatable {
        let browser: String
        let domain: String
        let title: String?
        let ytChannel: String?
        let ytCategory: String?
        let category: ActivityCategory
        let isYouTubeEntertainment: Bool
    }

    private let store: SpanStore
    private let classifier: Classifier
    private let appleScript = AppleScriptBrowserReader()
    private var lastExtensionEvent: BrowserTabEvent?
    private var openWebSpan: WebSpanRecord?
    private var pendingWebSpans: [WebSpanRecord] = []
    private var lastFlushAt: Date = .now
    private var poller: Task<Void, Never>?

    private(set) var currentWeb: CurrentWeb?

    static let supportedBrowserBundleIds: Set<String> = [
        "com.apple.Safari",
        "com.google.Chrome",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.vivaldi.Vivaldi",
        "company.thebrowser.Browser",
        "org.mozilla.firefox",
    ]

    init(store: SpanStore, classifier: Classifier) {
        self.store = store
        self.classifier = classifier
    }

    func start() {
        guard poller == nil else { return }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self, !Task.isCancelled else { return }
                await self.pollFrontmostBrowser()
            }
        }
    }

    func receiveExtensionEvent(_ event: BrowserTabEvent) {
        guard !event.incognito else { return }
        lastExtensionEvent = event
        let model = AppModel.shared
        guard model.settings.trackBrowsers else { return }
        if let frontBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           Self.supportedBrowserBundleIds.contains(frontBundle) {
            recordEvent(
                browser: event.browser,
                url: event.url,
                domain: event.domain ?? BrowserTabEvent.extractDomain(from: event.url),
                title: event.title,
                ytVideoId: event.ytVideoId ?? BrowserTabEvent.extractYouTubeVideoId(from: event.url),
                ytChannel: event.ytChannel,
                ytCategory: event.ytCategory,
                now: .now
            )
        }
    }

    func pollFrontmostBrowser() async {
        let model = AppModel.shared
        guard model.settings.trackBrowsers else {
            closeAndFlush(at: .now)
            currentWeb = nil
            return
        }
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleId = front.bundleIdentifier,
              Self.supportedBrowserBundleIds.contains(bundleId) else {
            closeOpenSpan(at: .now)
            currentWeb = nil
            flushIfNeeded(force: false, now: .now)
            return
        }

        if bundleId == "org.mozilla.firefox" {
            // Firefox has no AppleScript URL access: rely on extension events.
            if let ext = lastExtensionEvent, ext.browser.lowercased().contains("firefox"),
               Int64(Date.now.timeIntervalSince1970) - ext.ts < 60 {
                recordEvent(
                    browser: "Firefox",
                    url: ext.url,
                    domain: ext.domain ?? BrowserTabEvent.extractDomain(from: ext.url),
                    title: ext.title,
                    ytVideoId: ext.ytVideoId ?? BrowserTabEvent.extractYouTubeVideoId(from: ext.url),
                    ytChannel: ext.ytChannel,
                    ytCategory: ext.ytCategory,
                    now: .now
                )
            }
            return
        }

        if let sample = await appleScript.readActiveTab(bundleId: bundleId) {
            var ytChannel = sample.ytChannel
            var ytCategory = sample.ytCategory
            var ytVideoId = sample.ytVideoId
            if let ext = lastExtensionEvent,
               let extUrl = ext.url,
               let sampleUrl = sample.url,
               extUrl == sampleUrl || (ytVideoId != nil && ext.ytVideoId == ytVideoId) {
                ytChannel = ext.ytChannel ?? ytChannel
                ytCategory = ext.ytCategory ?? ytCategory
                ytVideoId = ext.ytVideoId ?? ytVideoId
            }
            recordEvent(
                browser: sample.browser,
                url: sample.url,
                domain: sample.domain,
                title: sample.title,
                ytVideoId: ytVideoId,
                ytChannel: ytChannel,
                ytCategory: ytCategory,
                now: .now
            )
        }
    }

    func closeAndFlush(at now: Date = .now) {
        closeOpenSpan(at: now)
        flushIfNeeded(force: true, now: now)
    }

    private func recordEvent(
        browser: String,
        url: String?,
        domain: String?,
        title: String?,
        ytVideoId: String?,
        ytChannel: String?,
        ytCategory: String?,
        now: Date
    ) {
        guard let domain, !domain.isEmpty else { return }
        let model = AppModel.shared
        let trackYT = model.settings.trackYouTube
        let res = classifier.classifyWeb(
            domain: domain,
            url: url,
            title: title,
            ytChannel: trackYT ? ytChannel : nil,
            ytVideoId: trackYT ? ytVideoId : nil,
            ytCategory: trackYT ? ytCategory : nil,
            ytPolicy: model.settings.youtubePolicy
        )
        let isYTEntertainment = (domain.contains("youtube.com") || domain.contains("youtu.be"))
            && res.category == .distracting
            && (ytCategory != nil || res.source == .youtube)

        currentWeb = CurrentWeb(
            browser: browser,
            domain: domain,
            title: title,
            ytChannel: ytChannel,
            ytCategory: ytCategory,
            category: res.category,
            isYouTubeEntertainment: isYTEntertainment
        )

        let ts = Int64(now.timeIntervalSince1970)
        let sessionId = model.currentSessionDBId
        let sessionKind = model.state.phase.kind?.dbKind

        if var current = openWebSpan {
            if current.domain == domain &&
               current.url == url &&
               current.ytCategory == ytCategory &&
               current.sessionId == sessionId &&
               current.category == res.category.rawValue {
                current.endedAt = ts
                openWebSpan = current
                flushIfNeeded(force: false, now: now)
                return
            }
            current.endedAt = max(current.startedAt, ts)
            if current.endedAt > current.startedAt {
                pendingWebSpans.append(current)
            }
        }

        openWebSpan = WebSpanRecord(
            browser: browser,
            url: url,
            domain: domain,
            title: title,
            ytVideoId: trackYT ? ytVideoId : nil,
            ytChannel: trackYT ? ytChannel : nil,
            ytCategory: trackYT ? ytCategory : nil,
            startedAt: ts,
            endedAt: ts,
            sessionId: sessionId,
            sessionKind: sessionKind,
            category: res.category.rawValue,
            categorySource: res.source.rawValue
        )
        flushIfNeeded(force: false, now: now)
    }

    private func closeOpenSpan(at now: Date) {
        guard var current = openWebSpan else { return }
        let ts = Int64(now.timeIntervalSince1970)
        current.endedAt = max(current.startedAt, ts)
        if current.endedAt > current.startedAt {
            pendingWebSpans.append(current)
        }
        openWebSpan = nil
    }

    private func flushIfNeeded(force: Bool, now: Date) {
        guard !pendingWebSpans.isEmpty else { return }
        if force || pendingWebSpans.count >= 10 || now.timeIntervalSince(lastFlushAt) >= 30 {
            let batch = pendingWebSpans
            pendingWebSpans.removeAll()
            lastFlushAt = now
            try? store.writeBatch(appSpans: [], webSpans: batch)
        }
    }
}
