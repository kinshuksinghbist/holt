import AppKit
import ApplicationServices
import Foundation
import HoltCore

/// Tracks frontmost app spans (and AX window titles when Accessibility is granted),
/// excludes idle/sleep/lock periods, and batches writes to `SpanStore`.
@MainActor
final class ActivityTracker {
    struct CurrentApp: Equatable {
        let bundleId: String
        let appName: String
        let windowTitle: String?
        let category: ActivityCategory
    }

    private let store: SpanStore
    private let classifier: Classifier
    private var openSpan: AppSpanRecord?
    private var pendingAppSpans: [AppSpanRecord] = []
    private var lastFlushAt: Date = .now
    private var workspaceObserver: NSObjectProtocol?
    private var isPausedAway = false

    private(set) var currentApp: CurrentApp?
    var onAppActivated: ((String, Date) -> Void)?

    init(store: SpanStore, classifier: Classifier) {
        self.store = store
        self.classifier = classifier
    }

    func start() {
        guard workspaceObserver == nil else { return }
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sampleFrontmostApp(enabled: AppModel.shared.settings.trackApps,
                                         trackTitles: AppModel.shared.settings.trackWindowTitles,
                                         isIdle: false,
                                         sessionId: AppModel.shared.currentSessionDBId,
                                         sessionKind: AppModel.shared.state.phase.kind?.dbKind)
            }
        }
    }

    func sampleFrontmostApp(
        enabled: Bool,
        trackTitles: Bool,
        isIdle: Bool,
        sessionId: Int64?,
        sessionKind: String?,
        now: Date = .now
    ) {
        guard enabled, !isPausedAway, !isIdle else {
            closeOpenSpan(at: now)
            flushIfNeeded(force: true, now: now)
            return
        }
        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleId = front.bundleIdentifier else {
            return
        }
        let appName = front.localizedName ?? bundleId
        let title = trackTitles ? readFocusedWindowTitle(pid: front.processIdentifier) : nil
        let res = classifier.classifyApp(bundleId: bundleId, appName: appName, windowTitle: title)
        let ts = Int64(now.timeIntervalSince1970)

        if currentApp?.bundleId != bundleId {
            onAppActivated?(bundleId, now)
        }
        currentApp = CurrentApp(bundleId: bundleId, appName: appName, windowTitle: title, category: res.category)

        if var current = openSpan {
            if current.bundleId == bundleId &&
               current.windowTitle == title &&
               current.sessionId == sessionId &&
               current.category == res.category.rawValue {
                current.endedAt = ts
                openSpan = current
                flushIfNeeded(force: false, now: now)
                return
            }
            current.endedAt = max(current.startedAt, ts)
            if current.endedAt > current.startedAt {
                pendingAppSpans.append(current)
            }
        }

        openSpan = AppSpanRecord(
            bundleId: bundleId,
            appName: appName,
            windowTitle: title,
            startedAt: ts,
            endedAt: ts,
            sessionId: sessionId,
            sessionKind: sessionKind,
            idle: 0,
            category: res.category.rawValue
        )
        flushIfNeeded(force: false, now: now)
    }

    func markAway(at now: Date = .now) {
        isPausedAway = true
        closeOpenSpan(at: now)
        flushIfNeeded(force: true, now: now)
    }

    func markBack() {
        isPausedAway = false
    }

    func flushNow(at now: Date = .now) {
        closeOpenSpan(at: now)
        flushIfNeeded(force: true, now: now)
    }

    private func closeOpenSpan(at now: Date) {
        guard var current = openSpan else { return }
        let ts = Int64(now.timeIntervalSince1970)
        current.endedAt = max(current.startedAt, ts)
        if current.endedAt > current.startedAt {
            pendingAppSpans.append(current)
        }
        openSpan = nil
    }

    private func flushIfNeeded(force: Bool, now: Date) {
        guard !pendingAppSpans.isEmpty else { return }
        if force || pendingAppSpans.count >= 10 || now.timeIntervalSince(lastFlushAt) >= 30 {
            let batch = pendingAppSpans
            pendingAppSpans.removeAll()
            lastFlushAt = now
            try? store.writeBatch(appSpans: batch, webSpans: [])
        }
    }

    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    private func readFocusedWindowTitle(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let appElement = AXUIElementCreateApplication(pid)
        var focusedWindow: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        guard err == .success, let window = focusedWindow, CFGetTypeID(window) == AXUIElementGetTypeID() else {
            return nil
        }
        let axWindow = unsafeBitCast(window, to: AXUIElement.self)
        var titleValue: CFTypeRef?
        let titleErr = AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleValue)
        guard titleErr == .success, let title = titleValue as? String else {
            return nil
        }
        return title
    }
}
