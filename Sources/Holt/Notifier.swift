import AppKit
import Foundation
import HoltCore
import UserNotifications

/// Notification types with their action buttons. With two or more actions macOS shows
/// them under an "Options" dropdown on the notification.
enum NotificationCategory: String, CaseIterable {
    case workDoneBreakRunning = "holt.work-done.break-running"
    case workDoneBreakReady = "holt.work-done.break-ready"
    case breakOver = "holt.break-over"
    case away = "holt.away"
    case workingTooLong = "holt.working-too-long"

    static let actionPrefix = "holt.action."
    static let snoozeTooLongID = "holt.custom.snooze-too-long"

    var actionDefinitions: [(id: String, title: String)] {
        switch self {
        case .workDoneBreakRunning:
            return [
                (Self.identifier(for: .endBreak), "Skip break"),
                (Self.identifier(for: .extend), "Keep going 10 m"),
                (Self.identifier(for: .endSession), "End for now"),
            ]
        case .workDoneBreakReady:
            return [
                (Self.identifier(for: .startNext), "Start break"),
                (Self.identifier(for: .extend), "Keep going 10 m"),
                (Self.identifier(for: .endSession), "End for now"),
            ]
        case .breakOver:
            return [
                (Self.identifier(for: .startNext), "Start next session"),
                (Self.identifier(for: .endSession), "End for now"),
            ]
        case .away:
            return [
                (Self.identifier(for: .resume), "Resume"),
                (Self.identifier(for: .endSession), "End for now"),
            ]
        case .workingTooLong:
            return [
                (Self.identifier(for: .takeBreak), "Take break"),
                (Self.snoozeTooLongID, "Snooze 20 m"),
            ]
        }
    }

    static func identifier(for action: SessionAction) -> String {
        actionPrefix + action.rawValue
    }

    static func action(for identifier: String) -> SessionAction? {
        guard identifier.hasPrefix(actionPrefix) else { return nil }
        return SessionAction(rawValue: String(identifier.dropFirst(actionPrefix.count)))
    }
}

/// Thin wrapper over macOS notifications — Holt's only outbound channel in Phase 1.
@MainActor
final class Notifier {
    static let shared = Notifier()

    /// The center holds its delegate weakly, so keep it alive here.
    private let presenter = NotificationPresenter()

    /// `UNUserNotificationCenter` crashes outside an app bundle (e.g. `swift run`), so guard on it.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func configure() {
        guard let center else { return }
        center.delegate = presenter
        let categories = NotificationCategory.allCases.map { category in
            UNNotificationCategory(
                identifier: category.rawValue,
                actions: category.actionDefinitions.map { item in
                    UNNotificationAction(identifier: item.id, title: item.title, options: [])
                },
                intentIdentifiers: [],
                options: []
            )
        }
        center.setNotificationCategories(Set(categories))
        // Callbacks arrive on a background queue: keep them @Sendable (non-main-actor).
        center.requestAuthorization(options: [.alert, .sound]) { @Sendable _, _ in }
    }

    func post(title: String, body: String, category: NotificationCategory? = nil) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let category { content.categoryIdentifier = category.rawValue }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { @Sendable _ in }
    }

    /// Removes Holt's notifications from Notification Center so stale action buttons can't
    /// act on a later session.
    func clearDelivered() {
        center?.removeAllDeliveredNotifications()
    }
}

/// Shows notifications even while Holt is frontmost, and routes action buttons to the model.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.actionIdentifier
        await MainActor.run {
            AppModel.shared.handleNotificationAction(identifier)
        }
    }
}

enum HoltResources {
    static let bundle: Bundle = {
        if let url = Bundle.main.url(forResource: "Holt_Holt", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return Bundle.module
    }()
}

/// Plays bundled Holt sounds, macOS system sounds, or a user-chosen file with volume control.
@MainActor
enum Sounds {
    private static func bundledSound(named name: String) -> NSSound? {
        guard let url = HoltResources.bundle.url(forResource: name, withExtension: "wav", subdirectory: "Sounds")
            ?? HoltResources.bundle.url(forResource: name, withExtension: "wav") else {
            return nil
        }
        return NSSound(contentsOf: url, byReference: true)
    }

    private static let holtWorkDone = bundledSound(named: "holt_work_done")
    private static let holtBreakOver = bundledSound(named: "holt_break_over")
    private static let holtStep = bundledSound(named: "holt_step")
    private static let holtBlop = bundledSound(named: "holt_blop")

    private static let sysWorkDone = NSSound(named: NSSound.Name("Glass"))
    private static let sysBreakOver = NSSound(named: NSSound.Name("Hero"))
    private static let sysRelease = NSSound(named: NSSound.Name("Pop"))
    private static let sysStep = NSSound(named: NSSound.Name("Tink"))

    static func playWorkDone(settings: AppSettings) {
        guard settings.playSounds else { return }
        let sound: NSSound?
        switch settings.soundChoice {
        case .holt:
            sound = holtWorkDone ?? sysWorkDone
        case .system:
            sound = sysWorkDone
        case .custom:
            if let path = settings.customSoundPath, !path.isEmpty {
                sound = NSSound(contentsOfFile: path, byReference: true) ?? holtWorkDone ?? sysWorkDone
            } else {
                sound = holtWorkDone ?? sysWorkDone
            }
        }
        play(sound, volume: settings.soundVolume)
    }

    static func playBreakOver(settings: AppSettings) {
        guard settings.playSounds else { return }
        let sound = settings.soundChoice == .system ? sysBreakOver : (holtBreakOver ?? sysBreakOver)
        play(sound, volume: settings.soundVolume)
    }

    static func playRelease(settings: AppSettings) {
        guard settings.playSounds else { return }
        let sound = settings.soundChoice == .system ? sysRelease : (holtBlop ?? sysRelease)
        play(sound, volume: settings.soundVolume * 0.85)
    }

    static func playStep(settings: AppSettings) {
        guard settings.playSounds else { return }
        let sound = settings.soundChoice == .system ? sysStep : (holtStep ?? sysStep)
        play(sound, volume: settings.soundVolume * 0.35)
    }

    private static func play(_ sound: NSSound?, volume: Double) {
        guard let sound else { return }
        sound.stop()
        sound.volume = Float(min(max(volume, 0), 1))
        sound.play()
    }
}

/// Tactile feedback for the jelly: trackpad haptic + a soft tick.
@MainActor
enum Feedback {
    static func step(haptics: Bool, settings: AppSettings) {
        if haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        Sounds.playStep(settings: settings)
    }
}
