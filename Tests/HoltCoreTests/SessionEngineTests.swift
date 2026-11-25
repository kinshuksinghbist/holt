import Foundation
import Testing
@testable import HoltCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }
private let minute = 60.0

@Suite("SessionEngine")
struct SessionEngineTests {
    @Test func startWorkRunsForConfiguredLength() {
        var s = SessionState()
        #expect(s.perform(.startWork, now: t0) == [.started(.work)])
        #expect(s.remaining(at: t0) == 25 * minute)
        #expect(s.remaining(at: at(10 * minute)) == 15 * minute)
        #expect(s.progress(at: at(12.5 * minute)) == 0.5)
    }

    @Test func customDurationFromStretchyTimer() {
        var s = SessionState()
        s.perform(.startWork, now: t0, duration: 50 * minute)
        #expect(s.remaining(at: t0) == 50 * minute)
    }

    @Test func tickBeforeDeadlineDoesNothing() {
        var s = SessionState()
        s.perform(.startWork, now: t0)
        #expect(s.tick(now: at(25 * minute - 1)).isEmpty)
    }

    @Test func completingWorkAutoStartsShortBreak() {
        var s = SessionState()
        s.perform(.startWork, now: t0)
        #expect(s.tick(now: at(25 * minute)) == [.completed(.work), .started(.shortBreak)])
        #expect(s.phase.kind == .shortBreak)
        #expect(s.completedInCycle == 1)
        #expect(s.completedTotal == 1)
    }

    @Test func lateTickAfterSleepStartsBreakAtNow() {
        var s = SessionState()
        s.perform(.startWork, now: t0)
        s.tick(now: at(60 * minute)) // Mac was asleep past the deadline
        #expect(s.remaining(at: at(60 * minute)) == 5 * minute)
    }

    @Test func fourthSessionEarnsLongBreakThenCycleResets() {
        var s = SessionState()
        var clock = t0
        for i in 1...4 {
            s.perform(.startWork, now: clock)
            if s.phase.kind != .work { s.perform(.startNext, now: clock) }
            clock = clock.addingTimeInterval(25 * minute)
            let fx = s.tick(now: clock)
            #expect(fx.last == .started(i == 4 ? .longBreak : .shortBreak))
            clock = clock.addingTimeInterval(s.config.duration(of: s.phase.kind!))
            s.tick(now: clock)
            #expect(s.phase == .ready(kind: .work))
        }
        #expect(s.completedInCycle == 0)
        #expect(s.cyclePosition == 1)
    }

    @Test func pauseAndResumeShiftDeadline() {
        var s = SessionState()
        s.perform(.startWork, now: t0)
        #expect(s.perform(.pause, now: at(10 * minute)) == [.paused(.user)])
        #expect(s.remaining(at: at(40 * minute)) == 15 * minute) // time frozen while paused
        #expect(s.perform(.resume, now: at(40 * minute)) == [.resumed])
        #expect(s.remaining(at: at(45 * minute)) == 10 * minute)
    }

    @Test func idleAutoPauseIsRetroactive() {
        var s = SessionState()
        s.perform(.startWork, now: t0)
        // Input stopped at minute 8; the idle threshold fired at minute 13.
        #expect(s.autoPause(reason: .idle, since: at(8 * minute)) == [.paused(.idle)])
        #expect(s.remaining(at: at(13 * minute)) == 17 * minute)
    }

    @Test func takingBreakEarlyDoesNotCountTowardCycle() {
        var s = SessionState()
        s.perform(.startWork, now: t0)
        #expect(s.perform(.takeBreak, now: at(20 * minute)) == [.endedEarly(.work), .started(.shortBreak)])
        #expect(s.completedInCycle == 0)
    }

    @Test func earlyBreakInLastSlotIsShortAndLongBreakStaysEarned() {
        var s = SessionState()
        var clock = t0
        for _ in 1...3 {
            s.perform(.startWork, now: clock)
            clock = clock.addingTimeInterval(25 * minute)
            s.tick(now: clock)               // completes work, auto-starts a short break
            s.perform(.endBreak, now: clock) // → next session ready
        }
        #expect(s.completedInCycle == 3)
        s.perform(.startNext, now: clock)
        // Abandoning the 4th session must not grant the long break.
        #expect(s.perform(.takeBreak, now: clock.addingTimeInterval(60)) == [.endedEarly(.work), .started(.shortBreak)])
        #expect(s.completedInCycle == 3)
        s.perform(.endBreak, now: clock.addingTimeInterval(120))
        s.perform(.startNext, now: clock.addingTimeInterval(120))
        // Actually completing the 4th session still earns it.
        #expect(s.tick(now: clock.addingTimeInterval(120 + 25 * minute)) == [.completed(.work), .started(.longBreak)])
    }

    @Test func endBreakLoadsNextSessionReady() {
        var s = SessionState()
        s.perform(.takeBreak, now: t0)
        #expect(s.perform(.endBreak, now: at(2 * minute)) == [.endedEarly(.shortBreak)])
        #expect(s.phase == .ready(kind: .work))
        #expect(s.perform(.startNext, now: at(3 * minute)) == [.started(.work)])
    }

    @Test func autoStartBreakOffLeavesBreakReady() {
        var s = SessionState(config: TimerConfig(autoStartBreak: false))
        s.perform(.startWork, now: t0)
        #expect(s.tick(now: at(25 * minute)) == [.completed(.work)])
        #expect(s.phase == .ready(kind: .shortBreak))
    }

    @Test func autoStartWorkChainsSessions() {
        var s = SessionState(config: TimerConfig(autoStartWork: true))
        s.perform(.startWork, now: t0)
        s.tick(now: at(25 * minute))
        #expect(s.tick(now: at(30 * minute)) == [.completed(.shortBreak), .started(.work)])
    }

    @Test func invalidActionsAreIgnored() {
        var s = SessionState()
        #expect(s.perform(.pause, now: t0).isEmpty)
        #expect(s.perform(.endBreak, now: t0).isEmpty)
        s.perform(.takeBreak, now: t0)
        #expect(s.perform(.pause, now: t0).isEmpty) // breaks don't pause
        #expect(s.perform(.startWork, now: t0).isEmpty)
    }

    @Test func controlsMatchSpec() {
        let cases: [(SessionPhase, [SessionAction])] = [
            (.idle, [.takeBreak, .startWork]),
            (.running(kind: .work, startedAt: t0, deadline: at(60), planned: 60), [.pause, .takeBreak, .endSession]),
            (.paused(kind: .work, remaining: 30, planned: 60, reason: .user), [.resume, .takeBreak, .endSession]),
            (.running(kind: .shortBreak, startedAt: t0, deadline: at(60), planned: 60), [.endBreak]),
            (.ready(kind: .work), [.startNext, .endSession]),
        ]
        for (phase, expected) in cases {
            var s = SessionState()
            s.phase = phase
            #expect(s.availableActions == expected, "phase \(phase)")
        }
    }

    @Test func stateSurvivesRelaunch() throws {
        var s = SessionState()
        s.perform(.startWork, now: t0)
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(SessionState.self, from: data) == s)
    }
}

@Suite("Voice & formatting")
struct VoiceTests {
    @Test func toneBands() {
        #expect(ToneBand(value: 0) == .polite)
        #expect(ToneBand(value: 0.5) == .punchy)
        #expect(ToneBand(value: 1) == .strict)
    }

    @Test func everyActionHasALabelInEveryTone() {
        for action in SessionAction.allCases {
            for tone in ToneBand.allCases {
                #expect(!Voice.label(for: action, tone: tone).isEmpty)
            }
        }
    }

    @Test func completionLinesExistAndAvoidAITells() throws {
        let banned = ["Great job", "I understand", "delve", "journey", "!!"]
        for tone in ToneBand.allCases {
            for seed in 0..<5 {
                let line = try #require(Voice.line(for: .completed(.work), tone: tone, seed: seed))
                #expect(line.count <= 140)
                #expect(banned.allSatisfy { !line.localizedCaseInsensitiveContains($0) })
            }
        }
    }

    @Test func clockFormat() {
        #expect(TimeFormat.clock(0) == "00:00")
        #expect(TimeFormat.clock(0.2) == "00:01")
        #expect(TimeFormat.clock(25 * 60) == "25:00")
        #expect(TimeFormat.clock(3725) == "1:02:05")
    }
}
