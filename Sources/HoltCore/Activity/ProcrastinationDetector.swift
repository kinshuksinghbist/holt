import Foundation

public enum ProcrastinationKind: String, Codable, Sendable {
    case distractingApp = "distracting_app"
    case distractingSite = "distracting_site"
    case ytEntertainment = "yt_entertainment"
    case rapidSwitching = "rapid_switching"
    case noSession = "no_session"
    case snoozeSpiral = "snooze_spiral"
    case screen = "screen"
}

public struct ProcrastinationAlert: Equatable, Sendable {
    public let kind: ProcrastinationKind
    public let subject: String
    public let ruleKind: RuleKind?
    public let rulePattern: String?
    public let durationSec: Int
    public let severity: Int // 1 = gentle (~60s), 2 = sharper (~3m), 3 = repeated + sound

    public init(
        kind: ProcrastinationKind,
        subject: String,
        ruleKind: RuleKind?,
        rulePattern: String?,
        durationSec: Int,
        severity: Int
    ) {
        self.kind = kind
        self.subject = subject
        self.ruleKind = ruleKind
        self.rulePattern = rulePattern
        self.durationSec = durationSec
        self.severity = severity
    }
}

/// Pure, deterministic procrastination detector per SPEC §11 and §15.
public struct ProcrastinationDetector: Equatable, Sendable {
    private var currentDistractionKey: String?
    private var distractionStartedAt: Date?
    private var firedLevel1 = false
    private var firedLevel2 = false
    private var lastLevel3At: Date?
    private var sameDayDistractionHits = 0
    private var currentDayKey: String?

    private var switchTimestamps: [Date] = []
    private var lastAppBundleId: String?
    private var lastRapidSwitchAlertAt: Date?

    private var activeWithoutSessionSince: Date?
    private var lastNoSessionAlertAt: Date?

    private var snoozeTimestamps: [Date] = []
    private var lastSnoozeSpiralAt: Date?

    public init() {}

    public mutating func recordAppSwitch(bundleId: String, now: Date) {
        if lastAppBundleId != bundleId {
            lastAppBundleId = bundleId
            switchTimestamps.append(now)
        }
        let cutoff = now.addingTimeInterval(-300)
        switchTimestamps.removeAll { $0 < cutoff }
    }

    public mutating func recordSnooze(now: Date) {
        snoozeTimestamps.append(now)
        let cutoff = now.addingTimeInterval(-3600)
        snoozeTimestamps.removeAll { $0 < cutoff }
    }

    public mutating func resetCurrentDistraction() {
        currentDistractionKey = nil
        distractionStartedAt = nil
        firedLevel1 = false
        firedLevel2 = false
    }

    public mutating func evaluate(
        now: Date,
        inWorkSession: Bool,
        isIdle: Bool,
        hasUndoneTodos: Bool,
        subjectName: String?,
        subjectKey: String?,
        ruleKind: RuleKind?,
        rulePattern: String?,
        category: ActivityCategory,
        isYouTubeEntertainment: Bool
    ) -> [ProcrastinationAlert] {
        let dayKey = HoltDay.key(for: now)
        if currentDayKey != dayKey {
            currentDayKey = dayKey
            sameDayDistractionHits = 0
        }

        var alerts: [ProcrastinationAlert] = []

        if inWorkSession && !isIdle {
            activeWithoutSessionSince = nil

            // 1. Rapid app switching (> 12 switches in 5 min)
            let cutoff = now.addingTimeInterval(-300)
            switchTimestamps.removeAll { $0 < cutoff }
            if switchTimestamps.count > 12 {
                if lastRapidSwitchAlertAt == nil || now.timeIntervalSince(lastRapidSwitchAlertAt!) >= 600 {
                    lastRapidSwitchAlertAt = now
                    alerts.append(ProcrastinationAlert(
                        kind: .rapidSwitching,
                        subject: "\(switchTimestamps.count) app switches in 5 min",
                        ruleKind: nil,
                        rulePattern: nil,
                        durationSec: 300,
                        severity: 2
                    ))
                }
            }

            // 2. Distracting app / site / YouTube entertainment
            if category == .distracting, let key = subjectKey, let name = subjectName {
                if currentDistractionKey != key {
                    currentDistractionKey = key
                    distractionStartedAt = now
                    firedLevel1 = false
                    firedLevel2 = false
                }
                if let started = distractionStartedAt {
                    let elapsed = Int(now.timeIntervalSince(started))
                    let kind: ProcrastinationKind = isYouTubeEntertainment ? .ytEntertainment : (ruleKind == .domain ? .distractingSite : .distractingApp)
                    if elapsed >= 180 && !firedLevel2 {
                        firedLevel2 = true
                        sameDayDistractionHits += 1
                        let sev = sameDayDistractionHits >= 3 ? 3 : 2
                        if sev == 3 { lastLevel3At = now }
                        alerts.append(ProcrastinationAlert(
                            kind: kind, subject: name, ruleKind: ruleKind, rulePattern: rulePattern,
                            durationSec: elapsed, severity: sev
                        ))
                    } else if elapsed >= 60 && !firedLevel1 {
                        firedLevel1 = true
                        sameDayDistractionHits += 1
                        let sev = (sameDayDistractionHits >= 3 && (lastLevel3At == nil || now.timeIntervalSince(lastLevel3At!) >= 300)) ? 3 : 1
                        if sev == 3 { lastLevel3At = now }
                        alerts.append(ProcrastinationAlert(
                            kind: kind, subject: name, ruleKind: ruleKind, rulePattern: rulePattern,
                            durationSec: elapsed, severity: sev
                        ))
                    }
                }
            } else {
                resetCurrentDistraction()
            }
        } else {
            resetCurrentDistraction()

            // 3. Active with todos but no session (>= 10 min active)
            if !inWorkSession && !isIdle && hasUndoneTodos {
                if activeWithoutSessionSince == nil {
                    activeWithoutSessionSince = now
                } else if let since = activeWithoutSessionSince, now.timeIntervalSince(since) >= 600 {
                    if lastNoSessionAlertAt == nil || now.timeIntervalSince(lastNoSessionAlertAt!) >= 1800 {
                        lastNoSessionAlertAt = now
                        alerts.append(ProcrastinationAlert(
                            kind: .noSession,
                            subject: "Active with todos pending",
                            ruleKind: nil,
                            rulePattern: nil,
                            durationSec: Int(now.timeIntervalSince(since)),
                            severity: 1
                        ))
                    }
                }
            } else {
                activeWithoutSessionSince = nil
            }
        }

        // 4. Snooze spiral (>= 3 snoozes in 60 min)
        let snoozeCutoff = now.addingTimeInterval(-3600)
        snoozeTimestamps.removeAll { $0 < snoozeCutoff }
        if snoozeTimestamps.count >= 3 {
            if lastSnoozeSpiralAt == nil || now.timeIntervalSince(lastSnoozeSpiralAt!) >= 1800 {
                lastSnoozeSpiralAt = now
                alerts.append(ProcrastinationAlert(
                    kind: .snoozeSpiral,
                    subject: "\(snoozeTimestamps.count) snoozes in the last hour",
                    ruleKind: nil,
                    rulePattern: nil,
                    durationSec: 3600,
                    severity: 2
                ))
            }
        }

        return alerts
    }
}
