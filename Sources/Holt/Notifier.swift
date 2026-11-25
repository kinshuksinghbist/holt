import AppKit
import Foundation
import UserNotifications

/// Thin wrapper over macOS notifications. Phase 1's only outbound channel.
@MainActor
final class Notifier {
    static let shared = Notifier()

    /// The center holds its delegate weakly, so keep it alive here.
    private let presenter = NotificationPresenter()

    /// `UNUserNotificationCenter` crashes outside an app bundle (e.g. `swift run`), so guard on it.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func requestAuthorization() {
        center?.delegate = presenter
        // Callbacks arrive on a background queue: keep them @Sendable (non-main-actor).
        center?.requestAuthorization(options: [.alert, .sound]) { @Sendable _, _ in }
    }

    func post(title: String, body: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        center.add(request) { @Sendable _ in }
    }
}

/// Without a delegate, macOS drops notifications posted while the app is frontmost
/// (e.g. while the main window is open). Always show them.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}

enum Sounds {
    @MainActor
    static func playCompletion() {
        // Placeholder until the custom Holt sound ships (M1).
        NSSound(named: NSSound.Name("Glass"))?.play()
    }
}
