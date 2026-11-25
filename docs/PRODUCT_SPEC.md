# Holt — Product Spec

> Holt is a local-first macOS accountability partner. He knows what you planned,
> what you're doing, what you finished, and — with great precision — what you
> didn't. He tells you about it, deadpan, through macOS notifications.

This is the **functional** spec: what the product does and how it behaves.
Visual design is out of scope except for structure (the UI uses a macOS
"glass" look: Liquid Glass on macOS 26, translucent materials on 14–15).
The engineering plan is in [PLAN.md](PLAN.md).

## Scope at a glance

| | Phase 1 (v1.0) | Phase 2 |
|---|---|---|
| Timer, menu bar panel, main window | ✅ | |
| Jelly stretch timer (sound + trackpad haptics) | ✅ | |
| Todos, lists, notes, history | ✅ | |
| App + website + YouTube tracking | ✅ | |
| Automatic screenshots → **on-device** OCR (Apple Vision) | ✅ (opt-in) | |
| Stats | ✅ | |
| Holt persona, tone slider, template voice | ✅ | |
| Nudges & reminders via **macOS notifications** | ✅ | |
| Sessions that start on their own | ✅ | |
| Walkthrough / onboarding | ✅ | |
| Notifications that drop out of the **notch** (Dynamic-Island style) | | ✅ |
| **Dock** features (live tile, Dock menu, drop to add) | | ✅ |
| **AI** (LLM-written lines, AI classification, AI screen understanding, AI voice) | | ✅ |
| Personality customization | | ✅ |
| Developer ID signing, notarization, auto-update | | ✅ |
| WhatsApp or any other messaging channel | ❌ removed | ❌ |

Holt talks **only through macOS** (notifications, the menu bar panel and the
app window). No phone, no WhatsApp, no network channel.

---

## 0. Product principles

1. **Holt is not a timer with jokes. He's a memory with opinions.** Every
   message is grounded in a real fact from the local database — a task, a
   count, a streak, a site, a time. Generic "stay focused!" lines are bugs.
2. **Local-first, private, offline.** All data lives in one SQLite file on
   your Mac. Phase 1 makes **no network calls at all**. Screenshots are read
   on-device and thrown away.
3. **Zero-friction start.** Focus is one click, one keystroke or one
   notification action away — and Holt can start it for you.
4. **Funny, never noisy.** Hard rate limits, quiet hours, cooldowns and
   de-duplication. Annoyance is the #1 reason people uninstall accountability
   apps.
5. **Honest numbers.** Idle, sleep, lock and paused time never count as focus.

---

## 1. Core purpose — what Holt knows

- What you **planned** (todos per day, per list).
- What you're **doing now** (session, task, frontmost app, site, video).
- What you **completed** (tasks, sessions, focus time).
- What you **skipped** today, **didn't do yesterday**, and **keep avoiding**
  (last week and beyond).
- How you **spend time** across apps and websites.
- Whether you're **actually working** during deep work.
- When you're **procrastinating** — and when you **deserve praise**.

History is first-class: rollover chains ("carried over 4 days"), skip counts,
abandoned sessions, best/worst hours and days.

> "You skipped the same task three times this week. At this point it's not a
> task. It's a recurring character flaw."

> "Two focused sessions before noon. Efficient. Frankly unsettling."

(All lines in this doc are original; see §3.)

---

## 2. Surfaces (Phase 1)

| Surface | What it is |
|---|---|
| **Menu bar item** | Always visible. Time left in the current work/break session, or an idle glyph. Click → panel. |
| **Menu bar panel** | Timer, animation, jelly timer, state controls, tone slider, today strip, latest Holt line, and a top-right button to open the full app. |
| **Main window** | Timer + animation hero (top ~30%), todos & lists, notes, stats, history, Holt feed, settings. |
| **macOS notifications** | All nudges, reminders, summaries. Action buttons — with 2+ actions macOS shows them in an **Options ▾** dropdown (the "dropdown button" from the brief). |
| **Browser extension** | For Firefox (required) and Chrome-family (optional, richer data): reports active tab URL/title and YouTube metadata to the app, locally. |
| **Walkthrough** | First-run onboarding + feature tour (§16). |

Phase 1 is **menu-bar-only** (no Dock icon). The Dock arrives in Phase 2 (§19).

---

## 3. Holt — personality

**Character.** Holt is the name and the persona. Deadpan, precise, formal,
sarcastic, observant, secretly proud of you — the archetype of a stoic,
by-the-book captain. Every line is **original writing**; the app ships no
quotes, catchphrases, images or audio from any TV show.

**Voice rules**
- Short: notifications ≤ 140 characters (title ≤ 40).
- Specific: each line references at least one concrete fact (task title,
  count, duration, site, streak, time of day).
- Unexpected vocabulary: mixes **archaic** ("forsooth", "thou hast
  squandered", "a most grievous dereliction", "hie thee hence") with
  **Gen-Z slang** ("no cap", "it's giving procrastination", "you ate",
  "lowkey", "touch grass", "main-character energy") — deadpan delivery of
  slang is the joke.
- **No AI-sounding text.** Banned: "Great job!", "I understand", "Remember,",
  "Let's", "delve", "journey", "it's important to", emoji strings, stacked
  exclamation marks. A test enforces this over every template.
- Never cruel about anything except your work habits (no identity, body,
  family, health jokes). Strict ≠ abusive.
- Profanity in Holt's lines only with the profanity toggle on (default: off).
  The one fixed exception is the punchy-tone start button, **"Get Shit Done"**,
  which always shows in the punchy tone regardless of the toggle;
  polite/strict tones use other wording.

**Tone slider** (panel + Settings), continuous with three anchors:

| | Polite | Punchy & fun (default) | Strict |
|---|---|---|---|
| Sarcasm | low | high | medium, colder |
| Praise | warm, frequent | dry, earned | rare |
| Taunts | none | playful | blunt, escalating |
| Start button | "Start focusing" | "Get Shit Done" | "Work. Now." |
| Reminder cadence | 0.6× | 1× | 1.5× |

Also: slang mix (archaic ↔ Gen-Z), profanity on/off, reminder intensity.

**How lines are made in Phase 1 — no AI.** A template engine (§13): a large
library of hand-written lines per trigger × tone band, with fact slots
(`{task}`, `{count}`, `{site}`, `{minutes}`, `{streak}`…), composable
openers/closers for variety, and a no-repeat memory. Phase 2 adds an
LLM writer on top of the same triggers and fact sheet.

---

## 4. Pomodoro / deep-work timer

### 4.1 Settings
- Work length (default 25 min; 5–180).
- Short break (default 5; 1–60). Long break (default 20; 5–120).
- Sessions before a long break (default 4; 2–12).
- Auto-start breaks (on). Auto-start next work session (off).
- Pause on inactivity (on), threshold **5 min**. Keyboard input counts as
  activity by default (toggle "cursor only" for the literal brief behaviour).
- "Working too long" threshold (90 min continuous work).
- Completion sound, volume, mute.

### 4.2 States
- **Idle** — nothing running.
- **Work running / Work paused** — pause reason recorded (you, idle, sleep,
  screen lock).
- **Break running** — short or long; long chosen from the cycle count.
- **Ready** — a session is loaded and waiting for Start (after a break, or
  after work if auto-start break is off).

### 4.3 Controls (same everywhere: panel, main window, notifications, hotkeys)

| State | Controls |
|---|---|
| Work running | **Pause session**, **Take break** (ends work, starts a break now), **End session** |
| Work paused | **Resume**, Take break, End session |
| Break running | **End break** (ends the break, loads the next session ready to start) |
| Ready | **Start**, End |
| Idle | **Take a break**, **Get Shit Done** (wording follows tone) |

### 4.4 Behaviour
- Deadline-based (wall clock): correct after sleep, App Nap, crash, relaunch.
- Sleep or screen lock during work → auto-pause; on return, resume prompt
  (auto-resume if away < 1 min).
- Idle pause is **retroactive**: the session pauses at the moment input
  stopped, so the idle minutes never count. Input resumes it.
- Taking a break or ending early never counts toward the long-break cycle.
- Working too long → notification suggesting a break.
- Global hotkeys: ⌃⌥Space start/pause, ⌃⌥B break, ⌃⌥E end (configurable).

### 4.5 Sessions that start on their own (off by default; offered in the walkthrough)
1. **Detected work:** no session + ≥ 2 min of continuous use of apps/sites
   marked productive → notification "Looks like work. Starting a 25-minute
   session in 10 s" with **Cancel** / **Not now (1 h)**.
2. **Scheduled focus blocks:** e.g. weekdays 10:00–12:00 → back-to-back
   sessions with breaks.
3. **Chained:** auto-start the next work session after a break (timer setting).

`session.started_by` records which (you / detected / schedule / chain /
notification) so stats and Holt can tell.

### 4.6 Session ↔ task
Optionally pick a task when starting (default: the task marked *doing*,
else the top undone task). Focus time rolls up per task: "3 h 40 m on
'Proposal' and it's still not done."

### 4.7 Jelly stretch timer
A tactile way to set any duration — the timer is a **jelly blob**:
- **Grab and stretch** the jelly outward; the further you pull, the longer
  the timer (5-min steps to 60 min, then 15-min steps to 3 h). The number
  updates live inside the jelly.
- It wobbles with soft-body spring physics; let go and it snaps into a
  round, taut shape at its new size, and the session starts (or waits for
  Start, per setting).
- As time runs, the jelly **slowly shrinks** back to rest size — a visual
  countdown. Pausing makes it jiggle in place.
- **Sound:** squishy stretch sound, a soft tick per step, a "blop" at the
  end.
- **Vibration:** trackpad haptic ticks at each step while dragging and a
  pulse at the end (Force Touch trackpads; Macs have no other vibration).
- Scroll over the jelly = ±1 min. Reduce Motion → plain ring slider.

---

## 5. Menu bar item & panel

**Title:** `▶ 18:42` (work), `☕ 03:10` (break), `⏸ 18:42` (paused), `◎`
(idle; optionally today's focus total). Monospaced digits so the bar doesn't
jiggle.

**Panel:**
- Top-right: **open the full app** (+ settings gear).
- Mode label (Deep work · 2 of 4 / Short break / Long break / Nothing going on).
- Timer + animation (§6) + jelly timer (§4.7).
- Current task (tap to change).
- State buttons (§4.3).
- Tone slider.
- Today strip: focus time, sessions done, todos left.
- Latest Holt line.

---

## 6. Timer animation

A replaceable animation layer driven by `mode` (work, break, long break, idle,
paused) and `progress` (0 → 1):
- **Work:** the mascot climbs a mountain — height reached = progress; at 1.0
  he plants a flag on the peak. Alternative scene: chopping a tree that falls
  at 1.0.
- **Break:** the mascot — a big guy, shirtless in shorts — chilling in the
  sun, or dancing with headphones; more relaxed as the break goes on.
- **Idle / "Get Shit Done":** custom idle loop.
- **Paused:** frozen mid-climb, tapping his foot.

Art is handled separately. Engineering: **Rive** state machine (`progress`,
`mode` inputs), with a built-in SwiftUI placeholder until the art lands.
Reduce Motion → static illustration at the current progress.

---

## 7. Main window

1. **Hero (~30% height):** same timer, animation, jelly and controls as the panel.
2. **Today:** todo lists (left), notes (right), Holt feed (strip).
3. **Stats** with range selector (§12).
4. **History:** calendar; a day shows its plan, done/skipped, sessions,
   app/site timeline, screen-observation labels and Holt's verdict.
5. **Settings** (§17).

---

## 8. Todos, lists, notes, history

### 8.1 Todos & lists
- Multiple lists (defaults Work, Personal, Health, Study, Admin, Errands; custom
  with name/colour/icon). Each list holds daily todos.
- Fields: title, list, day, status, estimate (pomodoros), priority, notes,
  link (file/URL), recurrence (daily / weekdays / weekly).
- Statuses: **todo → doing → done**, or **skipped** (optional reason), or
  **abandoned**. Every change is logged as an event.
- **Rollover:** at the day boundary (default 04:00) unfinished todos carry
  over; the new todo links to the old one so Holt can count "carried over
  4 days".
- Quick add: ⌘N, panel field, notification text-reply action.
- **Plan your day:** first activity of the day → sheet with yesterday's
  leftovers (keep / skip / drop) and recurring todos.

### 8.2 Notes
- A notes panel per day (scratchpad), per-task notes, optional per-session
  note at session end ("what did you do?").
- Skip reasons are notes.
- Holt reads notes: "You wrote 'finish proposal' and then spent 42 minutes on
  Reddit."

### 8.3 The fact sheet (Holt's memory)
Computed locally on demand; the single input to Holt's voice:
- Today: plan, done, doing, left; focus time; sessions done/abandoned; current
  session, task, app, site, video title; top distraction so far.
- Yesterday: what wasn't done; focus vs. average.
- Last 7 / 30 days: tasks skipped N times; longest rollover chain; abandoned
  sessions; best/worst hour and weekday; patterns ("you usually lose focus
  after 3 PM"); streaks.
- Holt's recent lines (no repeats) and how you reacted.

### 8.4 History tracked
Completed / not completed / skipped / rolled-over / repeatedly skipped /
started-but-abandoned tasks; done in vs. outside deep work; most-delayed
tasks; most productive days and hours.

---

## 9. App screen-time tracking
- Frontmost app continuously: name, bundle ID, window title (with
  Accessibility permission), start/end, session (work/break/none), idle flag.
- Idle, locked and asleep time excluded.
- Derived: time per app, focus count, **switches from → to**, work vs. break
  usage, apps that interrupt focus.
- ~200 common apps pre-categorized (productive / neutral / distracting);
  you can override any.

## 10. Browser & website tracking
- **Chrome and Firefox** (brief) + Safari, Arc, Brave, Edge.
- Per span: browser, URL, domain, title, start/end, session state, category,
  and where the category came from.
- Safari + Chromium browsers: read via Apple Events (macOS asks once per
  browser). **Firefox** needs the Holt extension; the extension also gives
  Chrome richer data.
- **YouTube:** video title, channel and YouTube's own category
  ("Entertainment", "Comedy", "Gaming", "Education", "Science & Technology"…).
  In a work session, an entertainment video → Holt calls you out by
  notification (escalating, §11).
- Classification (no AI in Phase 1): your rules → bundled domain list →
  YouTube category → title keywords → screen OCR (§14). Mark anything as
  "this is for work" from the notification or the stats screen.
- Rules editor: allow/deny lists, YouTube policy (always distracting /
  category-based / educational allowed during work).
- Private/incognito windows are not tracked.

## 11. Nudges & notifications (macOS notifications only)

| Trigger | Actions (Options ▾) |
|---|---|
| Active, no session, todos pending | Start 25 m · Start 50 m · Snooze 15 m · I'm on a break |
| Session started automatically | Cancel · Not now (1 h) |
| Work session complete (+ Holt sound) | Take break · Keep going 10 m · Mark task done |
| Break complete | Start next · 5 more minutes |
| Working too long | Take break · Snooze |
| Procrastinating in a session | Back to work · This is for work |
| Hourly / varied reminder | Start session · Open todos |
| Idle auto-pause | Resume |
| Morning brief / end-of-day summary / weekly review | Open Holt |
| Quick add | Text reply → new todo |

**Anti-spam policy:** max nudges per hour (default 4), quiet hours (default
22:00–08:00), per-trigger cooldowns, Focus/Do-Not-Disturb respected, no joke
repeated within 7 days, "Holt, quiet for 1 h" snooze-all.

**Escalation in a work session:** ~60 s on a distracting app/site →
notification; still there at ~3 min → sharper notification (strict wording);
repeated the same day → repeated notification + sound. (Time-sensitive
notifications that break through Focus need an Apple developer entitlement →
Phase 2.)

**Reminders** — hourly or "varied" (randomized 40–90 min, tone-scaled):
what's left today, what you didn't do yesterday, what you skipped last week,
a random stat to motivate or mock.

> "Hourly report: two tasks done, three untouched, one avoided with impressive
> consistency."

Walkthrough tip: set Holt's notification style to **Alerts** (persistent) so
action buttons stay on screen.

## 12. Stats

**Range selector:** Today · Yesterday · This week · Last week · This month ·
Custom.

**Core:** monthly **heatmap** (metric switch: focus minutes / sessions / tasks
done / focus score / distraction minutes); **daily work chart** (24-h ribbon
timeline of work / break / idle / distracted, coloured by category + focus
by hour); **top time**, **most shifted from**, **most shifted to**, **least
used**; app and website breakdowns (work vs. break, productive vs.
distracting, YouTube and entertainment time, distraction spikes).

**Creative ways to show time:**
- **Focus clock** — radial 24-h clock of when you work.
- **Switch river** — Sankey of app → app transitions.
- **Time exchange rate** — "41 min of YouTube = 1.6 sessions = most of a
  feature film"; rotating units.
- **Mountain log** — elevation the mascot climbed (1 work minute = 10 m;
  "Everest ×0.7 this month").
- **Holt's verdict** — one deadpan line summarizing the range (template).
- Cards: Best Focus Hour, Most Dangerous App, Longest Focus Streak, Fastest
  Derailment, Top Time Sink, Avoidance Champion, Comeback Day.

**Focus score:** 0–100 per day = completed focus ÷ planned, minus distraction
share and abandoned sessions; formula shown in a tooltip.

## 13. Holt's voice engine (Phase 1: templates)
- Triggers: session start/complete/abandon, break over, idle pause, working
  too long, distraction (by level), YouTube entertainment, no session while
  active, hourly/varied reminder, morning brief, end-of-day summary, weekly
  review, streak, comeback, task done, task skipped (by skip count), rollover.
- Each trigger has lines per tone band with fact slots, chosen only if the
  facts they need exist ("third time this week" only when count ≥ 3).
- Variety: openers × bodies × closers, archaic / Gen-Z variants, and a
  7-day no-repeat memory keyed per line.
- Quality gates (tests): ≤ 140 chars after slot filling, banned-phrase list,
  every slot resolvable, every trigger × tone has ≥ 8 lines.

## 14. Automatic screenshots — what are you actually doing? (opt-in, on-device)
- Needs Screen Recording permission; off until you turn it on.
- During work sessions, every N minutes (default 3) and when signals are
  ambiguous (unknown app, unclassified title), Holt captures the frontmost
  window at low resolution and runs **Apple Vision OCR on-device**.
- Phase 1 classification is rules over the OCR text: keyword/phrase sets per
  activity ("code", "docs", "email", "chat", "video", "shopping", "social
  feed", "game"), task-title matching for "on task?", and the frontmost app.
  Result: `label`, `onTask` (yes/no/unclear), `confidence`.
- The image is deleted immediately after OCR; only the label and a short
  keyword digest are stored. Never leaves the Mac.
- Never captures excluded apps (password managers, banking, Keychain Access,
  private browser windows, your exclusion list).
- Phase 2: AI-based understanding.

## 15. Procrastination detection
Signals: distracting app/site in a session, YouTube entertainment, rapid app
switching (> 12 switches in 5 min), long stays on non-work sites, active with
todos but no session, repeated snoozing, screen label "off task".
Actions: notification (escalating), procrastination event in the log,
mention in summaries and stats.
Settings: distracting/allowed apps & sites, YouTube policy, nudge frequency,
max warnings per hour, quiet hours.

## 16. Walkthrough & onboarding (≈ 3 min, skippable, resumable)
1. Meet Holt — choose a tone; sample lines update live as you move the slider.
2. Timer defaults — try the jelly.
3. Permissions, one screen each with why + live granted indicator + deep link
   to the right System Settings pane: Notifications (and Alerts style) →
   Accessibility → Automation per browser → Screen Recording (optional).
4. Browsers — install the extension for Firefox (and optionally Chrome).
5. Lists and today's first todos.
6. Open at login; sessions that start on their own.
7. Guided first session with coach-marks on the menu bar item and panel.
Later: contextual tips the first time a feature matters; "Replay tour" in
Settings.

## 17. Settings
- **Timer:** lengths, sessions before long break, auto-start break / next
  session, idle pause + threshold + cursor-only, working-too-long, hotkeys.
- **Holt:** tone slider, slang mix, profanity, reminder intensity, escalation.
- **Notifications:** per-trigger toggles, hourly vs. varied, quiet hours, max
  per hour, morning/evening/weekly summaries and their times.
- **Tracking:** apps, titles, browsers (per browser), YouTube detection,
  screenshots + interval + exclusions, categories editor, retention (raw 365
  days, rollups forever).
- **Startup:** open at login (starts tracking too), start tracking on launch.
- **Sound:** built-in Holt completion sound, custom sound file, volume, mute.
- **Data:** export (JSON + CSV), import, backup now / auto-backup, delete
  history (range), reset stats, show database in Finder.

## 18. A day with Holt (Phase 1)
1. Mac wakes; Holt starts at login and begins tracking.
2. First input → "Plan your day" with yesterday's 3 leftovers. Morning brief
   notification: "Yesterday: 4 of 7. The other 3 survived the night and are
   now today's problem."
3. You type in VS Code for 2 minutes → "Looks like work" auto-session
   (Cancel available). Mascot at base camp.
4. 12 minutes in, you open a YouTube video categorized Entertainment →
   notification at 60 s; sharper one at 3 min: "Twelve minutes into deep work
   and watching 'Top 50 Fails'. Bold. Wrong, but bold."
5. Back to work. Session completes: flag on the peak, Holt sound, "Session
   complete. No collapse into digital nonsense. Growth." Break auto-starts;
   the mascot sunbathes.
6. Break ends → next session ready; Start from the panel or the notification.
7. Varied reminders through the day.
8. 18:00 end-of-day summary notification → opens the day's recap.
9. Sunday: weekly review with the Avoidance Champion.

## 19. Phase 2
- **Notch notifications:** Holt's messages drop out of the notch like a
  Dynamic Island — a glass capsule that expands with the line and action
  buttons, then tucks back. Non-notch Macs: drops from the top-center of the
  menu bar. Native notifications remain as a fallback/setting.
- **Dock:** live countdown ring on the Dock icon, badge (todos left or
  minutes), right-click Dock menu with every control and quick durations,
  drop text/files on the icon to create todos, menu-bar-only toggle.
- **AI:** LLM-written lines from the same fact sheet (with template fallback
  and spend cap), AI classification of unknown sites/titles, AI screen
  understanding, optional spoken lines.
- **Personality customization:** packs/custom prompts.
- **Distribution:** Developer ID signing, notarization, auto-update.

## 20. Open questions (defaults chosen; tell me to change any)
1. Idle detection: keyboard counts as activity (default) — or literally cursor only?
2. Minimum macOS 14 Sonoma, Apple Silicon only — OK?
3. Tone slider: one slider with three anchors, Polite ↔ Punchy & fun
   (default, centre) ↔ Strict. The brief can also be read as two poles
   (punchy & fun ↔ polite/strict) — which do you want?
4. License for the public repo (MIT? none?) — your call.

Decided: the persona stays **Holt**, written as an original deadpan-captain
character (no show quotes or assets — needed for a public repo).
