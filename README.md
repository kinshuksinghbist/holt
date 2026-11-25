# Holt

**Your deadpan accountability partner for macOS.** Holt keeps track of what you
planned, what you're doing, what you finished and — with great precision — what
you didn't. He runs a Pomodoro timer in your menu bar, watches which apps and
sites eat your day, and tells you about it through macOS notifications, with
the warmth of a stapler.

> "Session complete. No collapse into digital nonsense. Growth."

Everything stays on your Mac: one local SQLite database (`~/Library/Application Support/Holt/holt.sqlite`), no account, no cloud, zero network calls in Phase 1.

## Status

**Phase 1 (`v1.0.0`) feature-complete** across milestones M0–M7. Built and tested on GitHub Actions (`macos-26` + `ubuntu-latest`):

- **Menu bar panel & main window** — AppKit `NSStatusItem` + `NSPopover` quick panel and multi-tab main window (`Today`, `History`, `Stats`).
- **Jelly stretch timer & Pomodoro engine** — grab the jelly and stretch it to pick any duration (5–60 min in 5s, then up to 3 h) with synthesized Holt chimes and trackpad haptics; shrinks as time runs, jiggles while paused, Reduce Motion support.
- **Focus guard & global hotkeys** — retroactive idle pause, sleep/lock auto-pause, working-too-long nudge, `"Keep going 10 m"` extension, and configurable Carbon hotkeys (`⌃⌥Space`, `⌃⌥B`, `⌃⌥E`).
- **Tasks, lists, notes & history** — SQLite via GRDB (`DatabasePool` WAL), default + custom lists, priorities, recurrence (`daily`/`weekdays`/`weekly`), rollover chains (`carried_from_id`, `root_id`), skip counts, day scratchpad + session notes, Plan Your Day sheet, `⌘N` / panel / notification text-reply quick add, JSON/CSV export & import, and 7-day rolling SQLite backups.
- **App, website & YouTube tracking** — frontmost app spans (with optional Accessibility window titles), Safari/Chromium AppleScript tracking, `holt-nm-host` native messaging binary + MV3 Firefox & Chrome extensions with YouTube category/channel extraction, ~200 apps & ~650 domains defaults, custom rules editor (`"This is for work"`), and escalating procrastination detector.
- **On-device screen understanding (opt-in)** — `ScreenCaptureKit` frontmost-window capture + Apple Vision OCR entirely in memory (images discarded immediately, never saved to disk), with built-in password manager / banking / private-window exclusions.
- **Stats & rollups** — incremental & nightly `daily_rollup` / `hourly_rollup`, range presets, Swift Charts monthly heatmap, hourly bars, 24-h radial Focus Clock, 24-h timeline ribbon, Canvas Switch River Sankey, time exchange rates, Mountain Log, 7 Creative Cards, Focus Score with formula tooltip, and Holt's verdict.
- **Holt's voice & nudges** — SQL-backed `FactSheet` (`"What Holt knows"` debug view), 432 original templates across 18 triggers × 3 tones in `Resources/voice/*.json`, 7-day no-repeat memory, slang mix & profanity controls, quiet hours, Focus/DND awareness, hourly/varied reminders, morning brief / EOD summary / weekly review, `"Holt, quiet for 1 h"`, and auto-sessions (detected productive work + scheduled focus blocks).
- **Animation & walkthrough** — `RiveRuntime` mascot layer (`progress` + `mode` state-machine inputs) with built-in SwiftUI `ClimbView` fallback, 7-step onboarding tour with live permission checks & System Settings deep links, and dismissible coach-marks.

The full product specification is in [docs/PRODUCT_SPEC.md](docs/PRODUCT_SPEC.md);
the engineering plan is in [docs/PLAN.md](docs/PLAN.md).

## Install a CI / Release build

Download `Holt.dmg` (and optionally the Firefox/Chrome companion extensions) from
the [GitHub Releases](../../releases) page or latest [CI run](../../actions/workflows/ci.yml),
open `Holt.dmg`, and drag Holt to `/Applications`.

Builds are **not notarized** (no Apple Developer ID in Phase 1), so macOS blocks
the first launch. Either:

- open **System Settings → Privacy & Security** and click **Open Anyway**, or
- run `xattr -dr com.apple.quarantine /Applications/Holt.app`.

Requires macOS 14 or later on Apple Silicon. Liquid Glass styling appears on
macOS 26.

## Build from source

```bash
swift test                # logic tests (HoltCore)
scripts/bundle-app.sh     # builds Holt + holt-nm-host and signs dist/Holt.app
scripts/make-dmg.sh       # packages dist/Holt.dmg
scripts/build-extension.sh # stages Firefox + Chrome MV3 extensions
```

Needs Xcode 26 (Swift 6.2+). CI is the reference build machine — see
[.github/workflows/ci.yml](.github/workflows/ci.yml).

### Optional: stable signing & Firefox extension signing in CI

- **macOS:** Add `MACOS_CERT_P12` (base64 `.p12`) and `MACOS_CERT_PASSWORD` secrets so privacy permissions survive app updates.
- **Firefox:** Add `AMO_JWT_ISSUER` and `AMO_JWT_SECRET` secrets so release tags sign the unlisted `.xpi` with Mozilla AMO.

## Project layout

```
Sources/HoltCore   pure Swift product logic (no UI) — engine, SQLite, voice, stats, tracking
Sources/Holt       SwiftUI + AppKit menu bar app
Sources/HoltNMHost native-messaging host binary embedded in Contents/Helpers
Tests/             swift-testing suites for HoltCore
extension/         MV3 WebExtension (Firefox + Chrome manifests & YouTube metadata)
Resources/         Info.plist, entitlements, app icon
scripts/           bundle, DMG, extension staging, CI signing
docs/              product spec and engineering plan
```

## About the persona

Holt is an original character: a stoic, precise, by-the-book captain type with
a dry sense of humour. All of his lines are written for this project.
