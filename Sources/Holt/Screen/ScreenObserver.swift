import AppKit
import CoreGraphics
import Foundation
import HoltCore
@preconcurrency import ScreenCaptureKit
import Vision

/// Opt-in, on-device screen understanding: captures frontmost window in memory, runs Apple Vision
/// OCR off the main actor, classifies with `ScreenLabeler`, and immediately discards the image.
@MainActor
final class ScreenObserver {
    private let screenStore: ScreenStore
    private var lastCaptureAt: Date = .distantPast
    private var isCapturing = false

    init(screenStore: ScreenStore) {
        self.screenStore = screenStore
    }

    static func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func maybeCapture(
        settings: AppSettings,
        inWorkSession: Bool,
        isAmbiguous: Bool,
        sessionId: Int64?,
        activeTaskTitle: String?,
        currentURL: String?,
        onOffTaskDetected: @escaping @MainActor (ScreenLabelResult) -> Void
    ) {
        guard settings.enableScreenUnderstanding, inWorkSession, !isCapturing else { return }
        guard Self.hasPermission() else { return }

        let now = Date.now
        let interval = TimeInterval(settings.screenIntervalMinutes * 60)
        let minCooldown: TimeInterval = isAmbiguous ? min(60, interval) : interval
        guard now.timeIntervalSince(lastCaptureAt) >= minCooldown else { return }

        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleId = front.bundleIdentifier else {
            return
        }
        let appName = front.localizedName ?? bundleId
        let windowTitle = AppModel.shared.currentAppWindowTitle
        if ScreenExclusions.shouldSkip(
            bundleId: bundleId,
            appName: appName,
            windowTitle: windowTitle,
            url: currentURL,
            userExclusions: settings.screenExclusions
        ) {
            return
        }

        let pid = front.processIdentifier
        lastCaptureAt = now
        isCapturing = true

        Task { [weak self] in
            defer { self?.isCapturing = false }
            guard let ocrText = await Self.captureAndOCR(pid: pid) else { return }
            let result = ScreenLabeler.label(
                ocrText: ocrText,
                bundleId: bundleId,
                appName: appName,
                windowTitle: windowTitle,
                activeTaskTitle: activeTaskTitle
            )
            let record = ScreenObservationRecord(
                ts: Int64(Date.now.timeIntervalSince1970),
                sessionId: sessionId,
                bundleId: bundleId,
                label: result.label.rawValue,
                onTask: result.onTask.rawValue,
                confidence: result.confidence,
                keywords: result.keywords.joined(separator: ",")
            )
            guard let self else { return }
            try? self.screenStore.record(record)
            if result.onTask == .no && result.confidence >= 0.65 {
                onOffTaskDetected(result)
            }
        }
    }

    private nonisolated static func captureAndOCR(pid: pid_t) async -> String? {
        guard let image = await captureFrontmostWindow(pid: pid) else { return nil }
        return recognizeText(in: image)
    }

    private nonisolated static func captureFrontmostWindow(pid: pid_t) async -> CGImage? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: {
                $0.owningApplication?.processID == pid &&
                $0.isOnScreen &&
                $0.frame.width > 120 &&
                $0.frame.height > 120
            }) else {
                return nil
            }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = min(Int(window.frame.width), 1280)
            config.height = min(Int(window.frame.height), 800)
            config.scalesToFit = true
            config.showsCursor = false
            return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            return nil
        }
    }

    private nonisolated static func recognizeText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        let observations = request.results ?? []
        return observations
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
