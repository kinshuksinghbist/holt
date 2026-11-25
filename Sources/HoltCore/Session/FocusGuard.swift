import Foundation

/// Tracks continuous work time across chained sessions so Holt can nudge when
/// you've been working too long without a real break.
public struct ContinuousWorkTracker: Equatable, Codable, Sendable {
    public private(set) var accumulatedSeconds: TimeInterval = 0
    public private(set) var lastSampleAt: Date?
    public private(set) var breakStartedAt: Date?
    public private(set) var snoozedUntil: Date?
    public private(set) var hasNudgedSinceReset = false

    public init() {}

    /// Advances tracking for the current session phase. Returns `true` when a
    /// "working too long" notification should fire.
    public mutating func update(
        phase: SessionPhase,
        now: Date,
        thresholdMinutes: Int,
        enabled: Bool
    ) -> Bool {
        switch phase {
        case .running(.work, _, _, _):
            breakStartedAt = nil
            if let last = lastSampleAt {
                let delta = now.timeIntervalSince(last)
                if delta > 0, delta < 300 {
                    accumulatedSeconds += delta
                }
            }
            lastSampleAt = now
            guard enabled else { return false }
            let threshold = TimeInterval(max(1, thresholdMinutes) * 60)
            guard accumulatedSeconds >= threshold else { return false }
            if let snoozedUntil, now < snoozedUntil { return false }
            if hasNudgedSinceReset {
                // Only fire again after a snooze expires.
                if let snoozedUntil, now >= snoozedUntil {
                    self.snoozedUntil = nil
                    return true
                }
                return false
            }
            hasNudgedSinceReset = true
            return true

        case .paused:
            lastSampleAt = nil
            return false

        case let .running(kind, _, _, _) where kind.isBreak:
            lastSampleAt = nil
            if breakStartedAt == nil {
                breakStartedAt = now
            } else if let started = breakStartedAt, now.timeIntervalSince(started) >= 60 {
                reset()
            }
            return false

        case .running:
            lastSampleAt = nil
            return false

        case .ready(.work):
            // Between sessions (e.g. after a break completed or was ended); if a break ran
            // long enough it already reset; otherwise leave accumulatedSeconds intact if
            // the user skipped a break immediately.
            lastSampleAt = nil
            if let started = breakStartedAt, now.timeIntervalSince(started) >= 60 {
                reset()
            }
            breakStartedAt = nil
            return false

        case .ready:
            lastSampleAt = nil
            return false

        case .idle:
            reset()
            return false
        }
    }

    public mutating func snooze(now: Date, minutes: Int = 20) {
        snoozedUntil = now.addingTimeInterval(TimeInterval(max(1, minutes) * 60))
    }

    public mutating func reset() {
        accumulatedSeconds = 0
        lastSampleAt = nil
        breakStartedAt = nil
        snoozedUntil = nil
        hasNudgedSinceReset = false
    }
}
