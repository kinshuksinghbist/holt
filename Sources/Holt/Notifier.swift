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

    static let actionPrefix = "holt.action."

    var actions: [SessionAction] {
        switch self {
        case .workDoneBreakRunning: [.endBreak, .endSession]
        case .workDoneBreakReady: [.startNext, .endSession]
        case .breakOver: [.startNext, .endSession]
        case .away: [.resume, .endSession]
        }
    }

    func title(for action: SessionAction) -> String {
        switch (self, action) {
        case (.workDoneBreakRunning, .endBreak): "Skip break"
        case (.workDoneBreakReady, .startNext): "Start break"
        case (.breakOver, .startNext): "Start next session"
        case (_, .endSession): "End for now"
        case (_, .resume): "Resume"
        default: Voice.label(for: action, tone: .punchy)
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
                actions: category.actions.map { action in
                    UNNotificationAction(
                        identifier: NotificationCategory.identifier(for: action),
                        title: category.title(for: action),
                        options: []
                    )
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

/// System sounds until the custom Holt sounds ship.
@MainActor
enum Sounds {
    private static let workDone = NSSound(named: NSSound.Name("Glass"))
    private static let breakOver = NSSound(named: NSSound.Name("Hero"))
    private static let release = NSSound(named: NSSound.Name("Pop"))
    private static let step: NSSound? = {
        let sound = NSSound(named: NSSound.Name("Tink"))
        sound?.volume = 0.25
        return sound
    }()

    static func playWorkDone() { replay(workDone) }
    static func playBreakOver() { replay(breakOver) }
    static func playRelease() { replay(release) }
    static func playStep() { replay(step) }

    private static func replay(_ sound: NSSound?) {
        guard let sound else { return }
        sound.stop()
        sound.play()
    }
}

/// Tactile feedback for the jelly: trackpad haptic + a soft tick.
@MainActor
enum Feedback {
    static func step(haptics: Bool, sound: Bool) {
        if haptics {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        if sound { Sounds.playStep() }
    }
}
