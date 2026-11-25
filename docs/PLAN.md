# Holt — Engineering Plan

Companion to [PRODUCT_SPEC.md](PRODUCT_SPEC.md): architecture, decisions,
data model, subsystem designs, milestones with acceptance criteria, CI/CD,
testing and risks. **All builds run on GitHub Actions** (public `macos-26`
runners); nothing needs to be built locally.

---

## 1. Architecture (Phase 1)

```
┌──────────────────────────── Holt.app (Swift 6, one process, menu-bar only) ───────────────────────────┐
│                                                                                                        │
│  UI (SwiftUI + AppKit)                  HoltCore (pure Swift, no UI imports, unit-tested)              │
│  ├─ MenuBarExtra panel                  ├─ Session/    SessionEngine (state machine, wall-clock)       │
│  ├─ Main window                         ├─ Tasks/      TaskStore, rollover, recurrence                 │
│  ├─ Jelly timer (Canvas + soft body)    ├─ Activity/   frontmost app, idle, sleep/lock, browsers       │
│  ├─ Animation (Rive / placeholder)      ├─ Classify/   rules → defaults → YouTube category → keywords  │
│  ├─ Onboarding + coach-marks            ├─ Screen/     ScreenCaptureKit + Vision OCR + rule labeler    │
│  └─ Settings                            ├─ Stats/      rollups + queries                               │
│                                         ├─ Holt/       FactSheet, NudgeEngine, Voice (templates)       │
│  System glue                            └─ Persistence/ GRDB, SQLite WAL, migrations                   │
│  ├─ UNUserNotificationCenter (actions)                                                                 │
│  ├─ SMAppService (open at login)                                                                       │
│  ├─ NSHapticFeedbackManager, NSSound                                                                   │
│  └─ Global hotkeys                                                                                     │
│                                       ▲ Unix domain socket (~/Library/Application Support/Holt)        │
└───────────────────────────────────────┼────────────────────────────────────────────────────────────────┘
                                        │
                 ┌──────────────────────┴────────────────┐      ┌──────────────────────────────────┐
                 │ holt-nm-host (tiny Swift CLI, bundled)│◀────▶│ Holt browser extension (MV3)     │
                 │ native-messaging host; relays tab and │stdio │ Firefox (required), Chrome-family│
                 │ YouTube events to the app             │      │ (optional, richer data)          │
                 └───────────────────────────────────────┘      └──────────────────────────────────┘
```

No servers, no ports, no network in Phase 1. The brief's "local server +
frontend client" is one always-running native app; the only extra process is
the native-messaging host, which browsers launch themselves.

## 2. Key decisions

| # | Decision | Why | Rejected |
|---|---|---|---|
| D1 | **Native Swift 6 + SwiftUI**, AppKit where needed | Menu bar, notifications, Accessibility, ScreenCaptureKit, Vision, haptics, Liquid Glass are native APIs; tiny CPU/RAM for an always-on app | Electron/Tauri |
| D2 | **SwiftPM only, no .xcodeproj**; `scripts/bundle-app.sh` assembles `Holt.app` | No pbxproj conflicts; plain `swift build` in CI; still opens in Xcode | XcodeGen/Tuist, checked-in pbxproj |
| D3 | **SQLite via GRDB.swift** (WAL, `DatabasePool`, versioned migrations) | Fast, proven, live observation for UI, analytics-friendly SQL, easy export | Core Data / SwiftData |
| D4 | **Append-only spans + daily/hourly rollups** | Raw spans are truth (re-classifiable); rollups make stats instant | Aggregates only |
| D5 | **Browsers: Apple Events for Safari + Chromium; extension for Firefox + rich YouTube data** | Firefox has no AppleScript URL access; the extension reads YouTube's own category | Accessibility scraping (fragile) |
| D6 | **Extension ↔ app via Native Messaging** | No open port; browser launches and authenticates the host | Localhost WebSocket |
| D7 | **Voice = template engine** (Phase 1) | Offline, free, deterministic, testable; Phase 2 adds an LLM on the same triggers + fact sheet | AI in v1 |
| D8 | **Screen understanding = Vision OCR + rules, on-device** | Private, free, fast; images discarded | Cloud vision |
| D9 | **Jelly timer = custom soft-body in SwiftUI `Canvas`** (ring of spring-mass points, Verlet integration, 120 Hz `TimelineView`) | Full control of feel; no dependency | SpriteKit (heavier), static slider |
| D10 | **Animations in Rive** (`progress`, `mode` inputs) with SwiftUI placeholder | Input-driven state machines, small files, macOS runtime | Lottie (no inputs), video |
| D11 | **Ad-hoc signing in CI, no Developer ID** (Phase 2 adds Developer ID + notarization + Sparkle) | No Apple account needed now | — |
| D12 | **macOS 14+, Apple Silicon**; Liquid Glass via `#available(macOS 26, *)` | `@Observable`, modern SwiftUI | Intel |
| D13 | **Menu-bar-only in Phase 1** (`LSUIElement`) | Dock features are Phase 2 | — |

### Signing without a Developer ID — what it means
- CI signs **ad-hoc** with the hardened runtime. Users open the first launch via
  **System Settings → Privacy & Security → Open Anyway** (macOS 15+), or run
  `xattr -dr com.apple.quarantine /Applications/Holt.app`.
- macOS ties privacy permissions (Accessibility, Screen Recording, Automation)
  to the code signature. An ad-hoc signature changes every build, so **each
  new build asks for those permissions again**.
- Fix without paying Apple: an optional **self-signed certificate** stored as
  a repo secret (`MACOS_CERT_P12`, `MACOS_CERT_PASSWORD`). CI signs with it;
  the designated requirement stays stable, so permissions survive updates.
  The workflow uses it automatically when the secrets exist and falls back to
  ad-hoc otherwise.

## 3. Repository layout

```
holt/
├─ Package.swift              # HoltCore (lib), Holt (app), holt-nm-host (M3), tests
├─ Sources/
│  ├─ HoltCore/               # all logic, no SwiftUI
│  ├─ Holt/                   # the app: MenuBar, MainWindow, Jelly, Onboarding, Settings
│  └─ HoltNMHost/             # (M3) native-messaging host
├─ Tests/HoltCoreTests/       # swift-testing
├─ extension/                 # (M3) MV3 WebExtension, Chrome + Firefox manifests
├─ Resources/                 # Info.plist, entitlements, sounds, Rive files, app icon
├─ scripts/                   # bundle-app.sh, make-dmg.sh, ci-signing.sh
├─ docs/                      # spec, plan, persona guide, ADRs
└─ .github/workflows/         # ci.yml, release.yml
```

## 4. Data model (SQLite via GRDB; lands in M2)

Times are UTC epoch seconds; `day` is the local "Holt day" (`YYYY-MM-DD`,
rolls over at the configured hour, default 04:00).

```sql
CREATE TABLE setting (key TEXT PRIMARY KEY, value TEXT NOT NULL);           -- JSON

CREATE TABLE list (id INTEGER PRIMARY KEY, name TEXT NOT NULL, color TEXT, icon TEXT,
  sort INTEGER NOT NULL DEFAULT 0, archived_at INTEGER);

CREATE TABLE task (
  id INTEGER PRIMARY KEY, list_id INTEGER REFERENCES list(id),
  title TEXT NOT NULL, notes TEXT, day TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('todo','doing','done','skipped','abandoned')),
  priority INTEGER NOT NULL DEFAULT 0, estimate_pomos INTEGER, link TEXT, recurrence TEXT,
  carried_from_id INTEGER REFERENCES task(id),   -- rollover chain
  root_id INTEGER REFERENCES task(id),           -- first task of the chain (skip counts)
  created_at INTEGER NOT NULL, completed_at INTEGER, skip_reason TEXT);
CREATE INDEX task_day ON task(day); CREATE INDEX task_root ON task(root_id);

CREATE TABLE task_event (id INTEGER PRIMARY KEY, task_id INTEGER NOT NULL REFERENCES task(id),
  ts INTEGER NOT NULL, kind TEXT NOT NULL, meta TEXT);
  -- created|started|done|skipped|reopened|carried|snoozed|abandoned

CREATE TABLE note (id INTEGER PRIMARY KEY, day TEXT NOT NULL, task_id INTEGER, session_id INTEGER,
  body TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);

CREATE TABLE session (
  id INTEGER PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('work','short_break','long_break')),
  planned_sec INTEGER NOT NULL, cycle_index INTEGER NOT NULL, task_id INTEGER REFERENCES task(id),
  started_at INTEGER NOT NULL, ended_at INTEGER,
  end_reason TEXT,              -- completed|ended_early|converted_to_break|crashed
  active_sec INTEGER NOT NULL DEFAULT 0,
  started_by TEXT NOT NULL DEFAULT 'user');  -- user|detected|schedule|chain|notification (jelly release = user)
CREATE TABLE session_pause (id INTEGER PRIMARY KEY, session_id INTEGER NOT NULL REFERENCES session(id),
  started_at INTEGER NOT NULL, ended_at INTEGER, reason TEXT NOT NULL);  -- user|idle|sleep|lock

CREATE TABLE app_span (id INTEGER PRIMARY KEY, bundle_id TEXT NOT NULL, app_name TEXT NOT NULL,
  window_title TEXT, started_at INTEGER NOT NULL, ended_at INTEGER NOT NULL,
  session_id INTEGER, session_kind TEXT, idle INTEGER NOT NULL DEFAULT 0, category TEXT);
CREATE INDEX app_span_time ON app_span(started_at);

CREATE TABLE web_span (id INTEGER PRIMARY KEY, app_span_id INTEGER REFERENCES app_span(id),
  browser TEXT NOT NULL, url TEXT, domain TEXT NOT NULL, title TEXT,
  yt_video_id TEXT, yt_channel TEXT, yt_category TEXT,
  started_at INTEGER NOT NULL, ended_at INTEGER NOT NULL, session_id INTEGER, session_kind TEXT,
  category TEXT, category_source TEXT);   -- default|user|youtube|keyword|screen
CREATE INDEX web_span_time ON web_span(started_at);

CREATE TABLE screen_observation (id INTEGER PRIMARY KEY, ts INTEGER NOT NULL, session_id INTEGER,
  bundle_id TEXT, label TEXT, on_task TEXT, confidence REAL, keywords TEXT);  -- no images stored

CREATE TABLE category_rule (id INTEGER PRIMARY KEY,
  kind TEXT NOT NULL,       -- bundle|domain|url_regex|title_keyword|yt_channel|yt_video
  pattern TEXT NOT NULL, category TEXT NOT NULL, source TEXT NOT NULL,  -- default|user
  UNIQUE(kind, pattern));

CREATE TABLE procrastination_event (id INTEGER PRIMARY KEY, ts INTEGER NOT NULL, session_id INTEGER,
  kind TEXT NOT NULL, subject TEXT, duration_sec INTEGER, severity INTEGER NOT NULL);
  -- distracting_app|distracting_site|yt_entertainment|rapid_switching|no_session|snooze_spiral|screen

CREATE TABLE holt_message (id INTEGER PRIMARY KEY, ts INTEGER NOT NULL,
  channel TEXT NOT NULL,    -- notification|panel   (Phase 2: notch)
  trigger TEXT NOT NULL, tone REAL NOT NULL, template_id TEXT NOT NULL, text TEXT NOT NULL,
  delivered_at INTEGER, outcome TEXT);  -- acted|snoozed|dismissed|ignored

CREATE TABLE daily_rollup (day TEXT PRIMARY KEY, focus_sec INTEGER, break_sec INTEGER, idle_sec INTEGER,
  sessions_done INTEGER, sessions_abandoned INTEGER, tasks_planned INTEGER, tasks_done INTEGER,
  tasks_skipped INTEGER, distract_sec INTEGER, switches INTEGER, focus_score INTEGER,
  top_app TEXT, top_site TEXT, computed_at INTEGER NOT NULL);
CREATE TABLE hourly_rollup (day TEXT, hour INTEGER, focus_sec INTEGER, distract_sec INTEGER,
  PRIMARY KEY (day, hour));
```

A retention job deletes raw spans older than the setting once their rollups
are final; rollups are kept forever.

## 5. Subsystem designs

### 5.1 SessionEngine — *implemented in M0*
- Value-type state machine: `perform(action, now)`, `tick(now)`,
  `autoPause(reason, since)` → `[SessionEffect]`. Time is always passed in,
  so tests are deterministic (sleep, idle retro-pause, cycles, relaunch).
- Deadline-based; pausing stores `remaining`, resuming sets a new deadline.
- Taking a break / ending early never advances the long-break cycle.
- One `SessionAction` list drives every control surface.

### 5.2 ActivityTracker (M3)
- `NSWorkspace.didActivateApplicationNotification` → close/open app spans;
  window title every 5 s via AX (`kAXFocusedWindowAttribute` →
  `kAXTitleAttribute`) when Accessibility is granted.
- Idle: `CGEventSource.secondsSinceLastEventType(.combinedSessionState, …)`
  every 5 s — no Input Monitoring permission needed; cursor-only mode uses
  `.mouseMoved`.
- Sleep/wake (`NSWorkspace.willSleep/didWake`), lock/unlock
  (`com.apple.screenIsLocked` / `…Unlocked` distributed notifications) →
  close spans, auto-pause the session.
- Batched writes (on change or every 30 s).

### 5.3 BrowserTracker (M3)
- Browser frontmost → every 3 s via precompiled `NSAppleScript`:
  Safari `{URL, name} of front document`; Chromium (Chrome, Brave, Edge, Arc,
  Vivaldi) `URL / title of active tab of front window`.
- Extension (MV3; Firefox manifest variant with `background.scripts` +
  `browser_specific_settings`): `tabs.onActivated/onUpdated`,
  `windows.onFocusChanged`; content script on YouTube watch pages reads
  category/channel/title (`ytInitialPlayerResponse.microformat` via an
  injected page script, plus `<meta itemprop="genre">` fallback, re-read on
  YouTube's SPA navigation event). Sent through `runtime.connectNative` to
  `holt-nm-host`, which relays over the app's Unix socket.
- The app installs the native-messaging manifests for each browser on
  enable (Chrome-family `…/<Browser>/NativeMessagingHosts/`, Firefox
  `~/Library/Application Support/Mozilla/NativeMessagingHosts/`).
- Incognito tabs ignored; private Safari windows skipped where detectable.

### 5.4 Classifier (M3)
First hit wins; cached per (kind, key): user rules → bundled defaults
(~200 apps, ~500 domains, JSON) → YouTube category map (Entertainment, Comedy,
Gaming, Music, People & Blogs → distracting; Education, Science & Technology,
Howto & Style → productive/neutral per setting) → title keywords → screen
label (§5.5).

### 5.5 ScreenObserver (M4, opt-in)
- `SCScreenshotManager` capture of the frontmost window, downscaled, every N
  minutes in work sessions + on ambiguity; skip excluded bundle IDs.
- `VNRecognizeTextRequest` (`.fast`, on-device) → text → rule labeler:
  weighted keyword sets per label + app prior + task-title token overlap →
  `{label, onTask, confidence}`. Image released immediately.
- Accuracy target: ≥ 80% on a 200-screenshot labelled set (kept out of the
  repo; fixtures are OCR text only).

### 5.6 FactSheet (M6)
`Codable` struct built from SQL in < 20 ms — the only input to the voice
engine. Shown verbatim in a debug view ("What Holt knows").

### 5.7 NudgeEngine (M6)
```
Triggers (timers + events) → Candidates {trigger, priority, facts}
  → Policy: quiet hours, Focus/DND, per-hour cap, cooldowns, snooze-all,
            escalation ladder, 7-day no-repeat
  → Voice: pick template (tone band, facts available, not recently used) → fill slots
  → Deliver: UNNotification (category with actions) | panel feed
  → Log holt_message; outcome updated from the notification response
```
"Varied" cadence = base × tone multiplier × jitter(0.7–1.3); suppressed while
you're in a session and on task.

### 5.8 Voice (M6; seed lines in M0)
- Templates in `Resources/voice/*.json`: `{id, trigger, tone, requires: [facts],
  text}`; ≥ 8 lines per trigger × tone; archaic and Gen-Z variants.
- Tests: every slot resolvable, ≤ 140 chars filled with worst-case facts,
  banned phrases absent, coverage per trigger × tone.

### 5.9 Jelly timer (M1)
- Blob = ring of 24 point masses with spring links to neighbours and to a
  target radius; Verlet integration with damping in a `TimelineView(.animation)`.
- Drag: the grabbed side's points follow the pointer with falloff; stretch
  distance → duration via a piecewise curve (5-min steps to 60, 15-min to 180).
- Each step crossing: `NSHapticFeedbackManager.defaultPerformer.perform(.alignment, …)`
  + tick sound; release → spring settle + start.
- Running: target radius interpolates from stretched size → rest size by
  progress; pause → periodic jiggle impulse.
- Pure physics in HoltCore (`JellyPhysics`, unit-tested for stability:
  energy decays, no NaNs, bounded radius); rendering in the app.

### 5.10 UI notes
- `MenuBarExtra(.window)`; title uses monospaced digits.
- Main window: `NavigationSplitView`; the hero is the same view as the panel's.
- Notifications: `UNNotificationCategory` per trigger with
  `UNNotificationAction`s and a `UNTextInputNotificationAction` for quick add;
  a `UNUserNotificationCenterDelegate` so notifications also show while Holt is
  frontmost. Escalation level 3 = repeated notification + sound at the normal
  (`.active`) level: `.timeSensitive` needs the
  `com.apple.developer.usernotifications.time-sensitive` entitlement, which
  requires an Apple developer team → Phase 2 (P2.5).
- Charts: Swift Charts (heatmap `RectangleMark`, ribbon spans, hourly
  `BarMark`, radial `SectorMark`); Sankey with custom `Canvas`.
- Glass: one `holtGlass()` modifier — `.glassEffect` on macOS 26,
  `.ultraThinMaterial` before.
- Accessibility: VoiceOver labels, keyboard control, Reduce Motion paths.

## 6. Permissions

| Permission | For | Required? |
|---|---|---|
| Notifications | every nudge | yes |
| Accessibility | window titles | recommended |
| Automation (per browser) | Safari/Chromium URLs | per browser |
| Screen Recording | screenshots + OCR | opt-in |
| Login item (SMAppService) | open at login | optional |
| *(none)* | idle detection via CGEventSource | — |

## 7. Milestones

### Phase 1

**M0 — Foundations (this commit)**
- Repo; SwiftPM package; `SessionEngine` + seed template voice + tests;
  menu-bar app with a working Pomodoro (start / pause / resume / take break /
  end / end break / start next), tone slider, completion sound + notification,
  placeholder climb animation, glass styling; bundle + DMG scripts; CI that
  tests, builds, ad-hoc signs and uploads `Holt.dmg`; tag-triggered release.
- ✅ CI green on `macos-26`; the DMG artifact installs and runs a full
  work → break → ready cycle from the menu bar.

**M1 — Timer, panel & jelly**
- All timer settings + Settings window; state persisted (crash recovery);
  sleep/lock/idle auto-pause (retroactive); working-too-long; global hotkeys.
- Panel complete (§5 of spec) with task picker stub.
- Jelly stretch timer with sound + haptics; Reduce Motion fallback.
- Notification categories with actions for complete / break over; sound
  settings (built-in, custom file, volume, mute); open at login.
- ✅ Every state transition unit-tested incl. sleep/idle edges; jelly physics
  stability tests; manual QA checklist for sleep/lock.
- *Progress:* AppKit `NSStatusItem` + `NSPopover` menu bar icon, Carbon global hotkeys, working-too-long nudge, `extend` (Keep going 10 m) action, and custom bundled Holt WAV sounds implemented.

**M2 — Tasks, lists, notes, history**
- GRDB + migrations; lists, todos, statuses, events, rollover chains,
  recurrence; notes (day/task/session); plan-your-day sheet; quick add
  (⌘N, panel, notification text reply); main window Today + History; export/
  import JSON + CSV; nightly backup (keep 7).
- ✅ Rollover/skip-count queries tested with fixed clocks; migration tests.

**M3 — Tracking**
- ActivityTracker (apps, titles, idle, sleep/lock); BrowserTracker (Apple
  Events); extension (Chrome + Firefox) + `holt-nm-host` + manifest installer;
  YouTube metadata; Classifier + rules editor; procrastination detector.
- CI extension job incl. Mozilla (AMO) unlisted signing of the Firefox build
  on release tags (§8).
- ✅ 8-hour soak: < 1% CPU average, < 120 MB RSS; spans sum to awake time
  within 1%.

**M4 — Screen understanding (on-device)**
- ScreenObserver with exclusions, Vision OCR, rule labeler, History display.
- ✅ ≥ 80% label accuracy on the labelled set; image never written to disk.

**M5 — Stats**
- Rollups (incremental + nightly recompute); range selector; heatmap; ribbon;
  hourly bars; top / least / shifted-from / shifted-to; Sankey; focus clock;
  creative cards; exchange rates; mountain log; focus score.
- ✅ Stats render a 1-year synthetic DB in < 150 ms.

**M6 — Holt's voice & nudges**
- FactSheet; full template library; NudgeEngine with policy, escalation,
  no-repeat; reminders (hourly/varied); morning / end-of-day / weekly
  notifications; auto-session (detected work, schedules, chaining).
- ✅ Every trigger × tone yields a fact-grounded line; policy tests (caps,
  quiet hours, cooldowns) with fixed clocks.

**M7 — Animation, walkthrough, polish → v1.0**
- Rive runtime + art drop-in; onboarding (7 steps) + coach-marks + tips;
  empty/error states; VoiceOver audit; performance pass; README + screenshots.
- ✅ New user reaches a completed first session in < 5 minutes in hallway tests.

### Phase 2
- **P2.1 Notch notifications** — borderless non-activating `NSPanel` at the
  top-center of the built-in display, sized from `NSScreen.safeAreaInsets` and
  `auxiliaryTopLeftArea/RightArea` (notch width), capsule that springs open
  with the line + actions and collapses; non-notch fallback; setting to use
  native notifications instead.
- **P2.2 Dock** — `NSDockTile` live ring + badge, `applicationDockMenu`,
  drop-to-add, menu-bar-only toggle.
- **P2.3 AI** — LLM line writer on the fact sheet (template fallback, spend
  cap, payload viewer), AI classification of unknown sites/titles, AI screen
  understanding (on-device model first), optional spoken lines.
- **P2.4 Personality customization.**
- **P2.5 Distribution** — Developer ID, notarization, Sparkle updates, and
  entitlements that need an Apple developer team (time-sensitive
  notifications for escalation).

## 8. CI/CD (GitHub Actions — the only build machine)

**`ci.yml`** — every push to `main`, every PR, manual dispatch:
1. `macos-26` runner using the image's default Xcode 26.x (Swift 6.2); the
   Toolchain step prints the versions.
2. `swift test` (swift-testing) — HoltCore logic.
3. `scripts/bundle-app.sh` — `swift build -c release`, assemble `Holt.app`,
   version from run number, sign (self-signed cert if secrets exist, else
   ad-hoc) with hardened runtime, verify signature.
4. `scripts/make-dmg.sh` → `dist/Holt.dmg`.
5. Upload `Holt.dmg` as a workflow artifact (download from the run page).

**`release.yml`** — on tag `v*`: same build, then a GitHub Release with the
DMG and its SHA-256.

Later milestones add:
- **Extension job (Ubuntu, M3):** `web-ext lint` + `web-ext build` for the
  Chrome zip and Firefox package on every push. On `v*` tags only, the
  Firefox build is signed as an **unlisted (self-distributed) add-on** with
  `web-ext sign --channel=unlisted` using free AMO API keys stored as secrets
  `AMO_JWT_ISSUER` / `AMO_JWT_SECRET` — release Firefox refuses unsigned
  add-ons (they only load temporarily). The manifest version comes from the
  tag (AMO never signs the same version twice), and the fixed
  `browser_specific_settings.gecko.id` matches the native-messaging manifest's
  `allowed_extensions`. The signed `.xpi` and the Chrome zip are attached to
  the GitHub Release.
- `holt-nm-host` built and embedded in `Holt.app/Contents/Helpers`.
- SwiftLint / swift-format lint, Dependabot.

## 9. Quality bar
- HoltCore ≥ 80% line coverage; every state transition and policy rule tested.
- Performance: idle CPU < 0.3%; tracking < 1%; RSS < 120 MB; panel opens
  < 100 ms; stats < 150 ms.
- Reliability: timer survives crash/kill/reboot; DB integrity check at launch;
  nightly backups.
- Privacy: no network in Phase 1; screenshots never stored; full export and
  delete.
- Accessibility: VoiceOver, keyboard-only, Reduce Motion.

## 10. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Permissions re-prompt after every unsigned update | Optional self-signed cert secret for a stable signature; onboarding shows live permission status |
| Gatekeeper friction (no Developer ID) | README instructions; Phase 2 notarization |
| Notifications shown as banners hide actions | Onboarding asks for Alerts style; panel duplicates every action |
| Template voice gets repetitive | Large library, composable parts, 7-day no-repeat, fact-gated lines; Phase 2 AI |
| Browser APIs change (YouTube DOM, extension APIs) | Multiple metadata sources with fallbacks; tracking degrades to domain/title |
| Screenshot privacy | Opt-in, on-device, never stored, exclusions |
| Annoyance → uninstall | Caps, quiet hours, snooze-all, outcome tracking tunes cadence |
| Persona IP in a public repo | Original character writing; no show assets/quotes |
| Can't compile locally | CI is the build machine; logic isolated in HoltCore with fast tests |

## 11. Working agreements
- `main` stays releasable; feature branches + PRs once work is parallel; CI
  must be green.
- Conventional commits.
- Nothing is pushed to GitHub without the owner's explicit go-ahead for that push.
