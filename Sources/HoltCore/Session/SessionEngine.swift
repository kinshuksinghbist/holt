import Foundation

public enum SessionKind: String, Codable, Sendable, CaseIterable {
    case work, shortBreak, longBreak

    public var isBreak: Bool { self != .work }

    public var dbKind: String {
        switch self {
        case .work: "work"
        case .shortBreak: "short_break"
        case .longBreak: "long_break"
        }
    }

    public init?(dbKind: String) {
        switch dbKind {
        case "work": self = .work
        case "short_break": self = .shortBreak
        case "long_break": self = .longBreak
        default: return nil
        }
    }
}

public enum PauseReason: String, Codable, Sendable {
    case user, idle, sleep, lock
}

/// Where the timer is. Deadline-based so it stays correct across sleep, App Nap and relaunches.
public enum SessionPhase: Equatable, Codable, Sendable {
    case idle
    case running(kind: SessionKind, startedAt: Date, deadline: Date, planned: TimeInterval)
    case paused(kind: SessionKind, remaining: TimeInterval, planned: TimeInterval, reason: PauseReason)
    /// A session is loaded and waiting for Start (e.g. after a break ends).
    case ready(kind: SessionKind)

    public var kind: SessionKind? {
        switch self {
        case .idle: nil
        case let .running(kind, _, _, _), let .paused(kind, _, _, _), let .ready(kind): kind
        }
    }
}

/// Every user-facing control. The same list drives the menu bar panel, main window,
/// notification actions and global hotkeys (and, in Phase 2, the Dock menu).
public enum SessionAction: String, Codable, Sendable, CaseIterable {
    case startWork, takeBreak, pause, resume, endSession, endBreak, startNext, extend
}

/// Side effects the app layer should perform after a transition.
public enum SessionEffect: Equatable, Sendable {
    case started(SessionKind)
    case completed(SessionKind)
    case endedEarly(SessionKind)
    case paused(PauseReason)
    case resumed
    case extended
}

/// The Pomodoro state machine. A pure value type: all time comes in as `now`,
/// so every transition is deterministic and unit-testable.
public struct SessionState: Equatable, Sendable {
    public var phase: SessionPhase
    /// Work sessions completed since the last long break.
    public var completedInCycle: Int
    /// Work sessions completed in total (lifetime of this state).
    public var completedTotal: Int
    public var config: TimerConfig
    /// True right after a work session completed via `tick`, so `.extend` can continue work.
    public private(set) var justCompletedWork: Bool

    public init(config: TimerConfig = .default) {
        self.phase = .idle
        self.completedInCycle = 0
        self.completedTotal = 0
        self.config = config
        self.justCompletedWork = false
    }

    // MARK: Queries

    public func remaining(at now: Date) -> TimeInterval? {
        switch phase {
        case let .running(_, _, deadline, _): max(0, deadline.timeIntervalSince(now))
        case let .paused(_, remaining, _, _): remaining
        case let .ready(kind): config.duration(of: kind)
        case .idle: nil
        }
    }

    /// 0 → 1 progress through the current session (drives the climbing animation).
    public func progress(at now: Date) -> Double {
        switch phase {
        case let .running(_, _, _, planned), let .paused(_, _, planned, _):
            guard planned > 0, let left = remaining(at: now) else { return 0 }
            return min(1, max(0, 1 - left / planned))
        case .ready, .idle: return 0
        }
    }

    /// The break that follows the next completed work session.
    public var nextBreakKind: SessionKind {
        completedInCycle + 1 >= config.sessionsBeforeLongBreak ? .longBreak : .shortBreak
    }

    /// Focused seconds so far in the current work session (pauses and idle excluded); 0 otherwise.
    public func workSecondsDone(at now: Date) -> TimeInterval {
        switch phase {
        case let .running(.work, _, _, planned), let .paused(.work, _, planned, _):
            return max(0, planned - (remaining(at: now) ?? planned))
        default:
            return 0
        }
    }

    public var isPaused: Bool {
        if case .paused = phase { return true }
        return false
    }

    /// Applies new settings. The running session keeps its length; the next one uses the new config.
    public mutating func updateConfig(_ newConfig: TimerConfig) {
        config = newConfig
    }

    /// 1-based position of the current/next work session within the cycle.
    public var cyclePosition: Int {
        min(completedInCycle + 1, config.sessionsBeforeLongBreak)
    }

    public var availableActions: [SessionAction] {
        switch phase {
        case .idle: [.takeBreak, .startWork]
        case let .running(kind, _, _, _): kind == .work ? [.pause, .takeBreak, .endSession] : [.endBreak]
        case .paused: [.resume, .takeBreak, .endSession]
        case .ready: [.startNext, .endSession]
        }
    }

    // MARK: Transitions

    /// Applies a user action. Invalid actions for the current phase are ignored.
    @discardableResult
    public mutating func perform(_ action: SessionAction, now: Date, duration: TimeInterval? = nil) -> [SessionEffect] {
        guard availableActions.contains(action) || action == .startWork || action == .extend else { return [] }
        switch (action, phase) {
        case (.startWork, .idle), (.startWork, .ready):
            justCompletedWork = false
            return start(.work, now: now, duration: duration)

        case let (.startNext, .ready(kind)):
            justCompletedWork = false
            return start(kind, now: now, duration: duration)

        case (.takeBreak, .idle):
            justCompletedWork = false
            return start(.shortBreak, now: now, duration: duration)

        case (.takeBreak, .running(.work, _, _, _)), (.takeBreak, .paused(.work, _, _, _)):
            justCompletedWork = false
            // Ending work early never counts toward the cycle — honest numbers. The break is
            // long only if a long break was already earned (e.g. one was skipped from Ready).
            let earned: SessionKind = completedInCycle >= config.sessionsBeforeLongBreak ? .longBreak : .shortBreak
            return [.endedEarly(.work)] + start(earned, now: now, duration: duration)

        case let (.pause, .running(kind, _, deadline, planned)) where kind == .work:
            justCompletedWork = false
            phase = .paused(kind: kind, remaining: max(0, deadline.timeIntervalSince(now)), planned: planned, reason: .user)
            return [.paused(.user)]

        case let (.resume, .paused(kind, remaining, planned, _)):
            justCompletedWork = false
            phase = .running(kind: kind, startedAt: now, deadline: now.addingTimeInterval(remaining), planned: planned)
            return [.resumed]

        case let (.endSession, .running(kind, _, _, _)), let (.endSession, .paused(kind, _, _, _)):
            justCompletedWork = false
            if kind == .longBreak { completedInCycle = 0 }
            phase = .idle
            return [.endedEarly(kind)]

        case let (.endSession, .ready(kind)):
            justCompletedWork = false
            if kind == .longBreak { completedInCycle = 0 }
            phase = .idle
            return []

        case let (.endBreak, .running(kind, _, _, _)) where kind.isBreak:
            justCompletedWork = false
            if kind == .longBreak { completedInCycle = 0 }
            phase = .ready(kind: .work)
            return [.endedEarly(kind)]

        case let (.extend, .running(.work, startedAt, deadline, planned)):
            justCompletedWork = false
            let extra = duration ?? 10 * 60
            phase = .running(kind: .work, startedAt: startedAt, deadline: deadline.addingTimeInterval(extra), planned: planned + extra)
            return [.extended]

        case let (.extend, .paused(.work, remaining, planned, reason)):
            justCompletedWork = false
            let extra = duration ?? 10 * 60
            phase = .paused(kind: .work, remaining: remaining + extra, planned: planned + extra, reason: reason)
            return [.extended]

        case let (.extend, .running(kind, _, _, _)) where kind.isBreak,
             let (.extend, .ready(kind)) where kind.isBreak:
            guard justCompletedWork else { return [] }
            justCompletedWork = false
            completedInCycle = max(0, completedInCycle - 1)
            completedTotal = max(0, completedTotal - 1)
            let extra = duration ?? 10 * 60
            phase = .running(kind: .work, startedAt: now, deadline: now.addingTimeInterval(extra), planned: extra)
            return [.extended]

        default:
            return []
        }
    }

    /// Pauses a running work session as of `since` (e.g. when input stopped,
    /// so idle minutes are not counted), for a system-driven reason.
    @discardableResult
    public mutating func autoPause(reason: PauseReason, since: Date) -> [SessionEffect] {
        guard case let .running(.work, startedAt, deadline, planned) = phase else { return [] }
        justCompletedWork = false
        let pauseAt = max(since, startedAt)
        phase = .paused(kind: .work, remaining: max(0, deadline.timeIntervalSince(pauseAt)), planned: planned, reason: reason)
        return [.paused(reason)]
    }

    /// Advances time. Completes the running session if its deadline has passed.
    @discardableResult
    public mutating func tick(now: Date) -> [SessionEffect] {
        guard case let .running(kind, _, deadline, _) = phase, now >= deadline else { return [] }
        var effects: [SessionEffect] = [.completed(kind)]
        switch kind {
        case .work:
            let next = nextBreakKind
            completedInCycle += 1
            completedTotal += 1
            justCompletedWork = true
            if config.autoStartBreak {
                effects += start(next, now: now, duration: nil)
            } else {
                phase = .ready(kind: next)
            }
        case .shortBreak, .longBreak:
            justCompletedWork = false
            if kind == .longBreak { completedInCycle = 0 }
            if config.autoStartWork {
                effects += start(.work, now: now, duration: nil)
            } else {
                phase = .ready(kind: .work)
            }
        }
        return effects
    }

    private mutating func start(_ kind: SessionKind, now: Date, duration: TimeInterval?) -> [SessionEffect] {
        let planned = duration ?? config.duration(of: kind)
        phase = .running(kind: kind, startedAt: now, deadline: now.addingTimeInterval(planned), planned: planned)
        return [.started(kind)]
    }
}

extension SessionState: Codable {
    private enum CodingKeys: String, CodingKey {
        case phase, completedInCycle, completedTotal, config, justCompletedWork
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        phase = try c.decode(SessionPhase.self, forKey: .phase)
        completedInCycle = try c.decode(Int.self, forKey: .completedInCycle)
        completedTotal = try c.decode(Int.self, forKey: .completedTotal)
        config = try c.decode(TimerConfig.self, forKey: .config)
        justCompletedWork = try c.decodeIfPresent(Bool.self, forKey: .justCompletedWork) ?? false
    }
}
