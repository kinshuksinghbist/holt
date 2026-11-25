import Foundation
import HoltCore
import Observation

/// What the animation layer should show.
enum AnimationMode: Equatable {
    case idle, work, paused, rest
}

/// App-wide state: owns the session engine, ticks the clock and performs effects.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var state: SessionState
    private(set) var now: Date = .now
    private(set) var lastLine: String?
    /// Tone slider value: 0 polite · 0.5 punchy · 1 strict.
    var tone: Double

    @ObservationIgnored private var ticker: Task<Void, Never>?

    private enum Keys {
        static let state = "holt.sessionState"
        static let tone = "holt.tone"
    }

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.state),
           let saved = try? JSONDecoder().decode(SessionState.self, from: data) {
            state = saved
        } else {
            state = SessionState()
        }
        tone = defaults.object(forKey: Keys.tone) as? Double ?? 0.5
        startTicker()
    }

    // MARK: Derived values for the UI

    var toneBand: ToneBand { ToneBand(value: tone) }
    var remaining: TimeInterval? { state.remaining(at: now) }
    var progress: Double { state.progress(at: now) }

    var menuBarTitle: String {
        if case .idle = state.phase { return "" }
        return remaining.map(TimeFormat.clock) ?? ""
    }

    var menuBarSymbol: String {
        switch state.phase {
        case .idle:
            return "scope"
        case let .running(kind, _, _, _):
            return kind == .work ? "flame.fill" : "cup.and.saucer.fill"
        case .paused:
            return "pause.fill"
        case .ready:
            return "play.fill"
        }
    }

    var modeTitle: String {
        let cycle = "\(state.cyclePosition) of \(state.config.sessionsBeforeLongBreak)"
        switch state.phase {
        case .idle:
            return "Nothing going on"
        case let .running(kind, _, _, _):
            return Self.title(for: kind, cycle: cycle)
        case let .paused(kind, _, _, _):
            return Self.title(for: kind, cycle: cycle) + " · paused"
        case let .ready(kind):
            return kind == .work ? "Next session ready" : "Break ready"
        }
    }

    var animationMode: AnimationMode {
        switch state.phase {
        case .idle, .ready:
            return .idle
        case let .running(kind, _, _, _):
            return kind == .work ? .work : .rest
        case .paused:
            return .paused
        }
    }

    private static func title(for kind: SessionKind, cycle: String) -> String {
        switch kind {
        case .work: "Deep work · \(cycle)"
        case .shortBreak: "Short break"
        case .longBreak: "Long break"
        }
    }

    // MARK: Actions

    func perform(_ action: SessionAction) {
        now = .now
        handle(state.perform(action, now: now))
    }

    func saveTone() {
        UserDefaults.standard.set(tone, forKey: Keys.tone)
    }

    private func tick() {
        now = .now
        let effects = state.tick(now: now)
        if !effects.isEmpty { handle(effects) }
    }

    private func startTicker() {
        ticker = Task { [weak self] in
            // Complete anything that finished while the app was closed, then tick every second.
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func handle(_ effects: [SessionEffect]) {
        for effect in effects {
            guard let line = Voice.line(for: effect, tone: toneBand, seed: state.completedTotal) else { continue }
            lastLine = line
            if case let .completed(kind) = effect {
                if kind == .work { Sounds.playCompletion() }
                Notifier.shared.post(title: kind == .work ? "Session complete" : "Break's over", body: line)
            }
        }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: Keys.state)
        }
    }
}
