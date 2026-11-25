import Foundation
import Testing
@testable import HoltCore

@Suite("Voice library, FactSheet & Nudge policy")
struct VoiceLibraryTests {
    private let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    @Test func everyTriggerAndToneHasAtLeastEightValidTemplates() {
        let library = VoiceLibrary.shared
        let worstCaseSlots: [String: String] = [
            "task": "Refactor the entire authentication pipeline and write exhaustive migration docs",
            "count": "99",
            "site": "extremely-long-distracting-subdomain.socialnetwork.example.com",
            "app": "Discord Canary Enterprise Edition",
            "video": "Top 500 Unbelievable Compilation Fails Of The Entire Century",
            "minutes": "180",
            "hours": "42",
            "streak": "365",
            "score": "100",
            "days": "14",
            "skips": "19",
            "left": "25",
            "done": "18",
            "planned": "43",
            "yesterday_left": "12",
            "best_hour": "09:00",
            "distract": "95",
        ]

        for trigger in VoiceTrigger.allCases {
            for tone in ToneBand.allCases {
                let items = library.templates(for: trigger, tone: tone)
                #expect(items.count >= 8, "Missing coverage for \(trigger.rawValue)/\(tone.rawValue): \(items.count)")

                for tpl in items {
                    // Check every placeholder in template text is a known slot
                    let regex = try! NSRegularExpression(pattern: #"\{([a-z_]+)\}"#)
                    let ns = tpl.text as NSString
                    let matches = regex.matches(in: tpl.text, range: NSRange(location: 0, length: ns.length))
                    for m in matches {
                        let name = ns.substring(with: m.range(at: 1))
                        #expect(VoiceLibrary.supportedSlots.contains(name), "Unknown slot {\(name)} in \(tpl.id)")
                    }

                    // Check banned phrases
                    for phrase in VoiceLibrary.bannedPhrases {
                        #expect(!tpl.text.localizedCaseInsensitiveContains(phrase), "Banned '\(phrase)' in \(tpl.id)")
                    }

                    // Check filled length <= 140
                    let filled = VoiceLibrary.fill(template: tpl.text, slots: worstCaseSlots)
                    #expect(filled.count <= 140, "Too long (\(filled.count)): \(filled)")
                    #expect(!filled.contains("{"))
                }
            }
        }
    }

    @Test func sevenDayNoRepeatAndFactGating() throws {
        let db = try HoltDatabase.openInMemory()
        let store = TaskStore(db: db)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day = HoltDay.key(for: now, calendar: utc)
        _ = try store.createTask(title: "Write release notes", day: day, now: now)

        let facts1 = try FactSheetBuilder.build(db: db, now: now, calendar: utc)
        let first = VoiceLibrary.shared.render(trigger: .sessionStart, tone: .punchy, facts: facts1, seed: 0)
        #expect(first != nil)

        var facts2 = facts1
        facts2.recentTemplateIds = [first!.templateId]
        let second = VoiceLibrary.shared.render(trigger: .sessionStart, tone: .punchy, facts: facts2, seed: 0)
        #expect(second != nil)
        #expect(second!.templateId != first!.templateId)
    }

    @Test func factSheetBuildsQuickly() throws {
        let db = try HoltDatabase.openInMemory()
        let start = CFAbsoluteTimeGetCurrent()
        let facts = try FactSheetBuilder.build(db: db, now: .now)
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0
        #expect(elapsedMs < 50.0)
        #expect(facts.today.plannedCount == 0)
    }

    @Test func nudgePolicyEnforcesQuietHoursCapCooldownAndSnooze() {
        var settings = AppSettings()
        settings.quietHoursEnabled = true
        settings.quietStartHour = 22
        settings.quietEndHour = 8
        settings.maxNudgesPerHour = 4

        let quietNight = utc.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 23, minute: 30))!
        let earlyMorning = utc.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 6, minute: 15))!
        let daytime = utc.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 11, minute: 0))!

        #expect(!NudgePolicy.shouldDeliverNotification(
            trigger: .hourlyReminder, settings: settings, now: quietNight,
            isSystemFocusActive: false, snoozedAllUntil: nil, deliveredLastHour: 0, lastTriggerDeliveredAt: nil, calendar: utc
        ))
        #expect(!NudgePolicy.shouldDeliverNotification(
            trigger: .hourlyReminder, settings: settings, now: earlyMorning,
            isSystemFocusActive: false, snoozedAllUntil: nil, deliveredLastHour: 0, lastTriggerDeliveredAt: nil, calendar: utc
        ))
        #expect(NudgePolicy.shouldDeliverNotification(
            trigger: .hourlyReminder, settings: settings, now: daytime,
            isSystemFocusActive: false, snoozedAllUntil: nil, deliveredLastHour: 0, lastTriggerDeliveredAt: nil, calendar: utc
        ))

        // Focus DND blocks
        #expect(!NudgePolicy.shouldDeliverNotification(
            trigger: .hourlyReminder, settings: settings, now: daytime,
            isSystemFocusActive: true, snoozedAllUntil: nil, deliveredLastHour: 0, lastTriggerDeliveredAt: nil, calendar: utc
        ))
        // Per-hour cap blocks at 4
        #expect(!NudgePolicy.shouldDeliverNotification(
            trigger: .hourlyReminder, settings: settings, now: daytime,
            isSystemFocusActive: false, snoozedAllUntil: nil, deliveredLastHour: 4, lastTriggerDeliveredAt: nil, calendar: utc
        ))
        // Snooze-all blocks
        #expect(!NudgePolicy.shouldDeliverNotification(
            trigger: .hourlyReminder, settings: settings, now: daytime,
            isSystemFocusActive: false, snoozedAllUntil: daytime.addingTimeInterval(600), deliveredLastHour: 0, lastTriggerDeliveredAt: nil, calendar: utc
        ))
        // Cooldown blocks within 40 min for hourlyReminder
        #expect(!NudgePolicy.shouldDeliverNotification(
            trigger: .hourlyReminder, settings: settings, now: daytime,
            isSystemFocusActive: false, snoozedAllUntil: nil, deliveredLastHour: 0, lastTriggerDeliveredAt: daytime.addingTimeInterval(-600), calendar: utc
        ))
    }

    @Test func autoSessionDetectedWorkAndSchedules() {
        var monitor = AutoSessionMonitor()
        var settings = AppSettings()
        settings.autoSessionDetectedWork = true
        let t0 = utc.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 14, minute: 0))! // Wednesday

        // 0s..119s productive: no prompt yet
        let e0 = monitor.update(phase: .idle, isProductiveActivity: true, isIdle: false, settings: settings, now: t0, calendar: utc)
        #expect(e0 == nil)
        let e1 = monitor.update(phase: .idle, isProductiveActivity: true, isIdle: false, settings: settings, now: t0.addingTimeInterval(120), calendar: utc)
        #expect(e1 == .promptDetectedWork)

        // 10s grace expires -> startDetectedWork
        let e2 = monitor.update(phase: .idle, isProductiveActivity: true, isIdle: false, settings: settings, now: t0.addingTimeInterval(131), calendar: utc)
        #expect(e2 == .startDetectedWork)

        // Scheduled block triggers immediately when matching
        settings.scheduledFocusBlocks = [FocusBlockSchedule(label: "Afternoon Deep", weekdays: [4], startHour: 14, startMinute: 0, endHour: 16, endMinute: 0)]
        let e3 = monitor.update(phase: .idle, isProductiveActivity: false, isIdle: false, settings: settings, now: t0.addingTimeInterval(200), calendar: utc)
        #expect(e3 == .startScheduledBlock("Afternoon Deep"))
    }
}
