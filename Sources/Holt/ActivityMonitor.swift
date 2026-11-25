import AppKit
import CoreGraphics
import HoltCore

/// Watches for the user going away (sleep, screen lock) and coming back, and polls input
/// idleness. Needs no permissions: idle time comes from `CGEventSource`.
@MainActor
final class ActivityMonitor {
    var onAway: ((PauseReason) -> Void)?
    var onBack: (() -> Void)?
    var onPoll: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var poller: Task<Void, Never>?

    func start() {
        guard observers.isEmpty else { return }

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onAway?(.sleep)
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onBack?()
            }
        })

        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onAway?(.lock)
            }
        })
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onBack?()
            }
        })

        poller = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                self?.onPoll?()
            }
        }
    }

    /// Seconds since the last input. With `keyboardCounts` false, only pointer activity counts.
    func secondsSinceInput(keyboardCounts: Bool) -> TimeInterval {
        if keyboardCounts, let any = CGEventType(rawValue: ~0) {
            return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: any)
        }
        let pointer: [CGEventType] = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .rightMouseDown, .scrollWheel]
        return pointer
            .map { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: $0) }
            .min() ?? 0
    }
}
