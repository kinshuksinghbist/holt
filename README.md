# Holt

**Your deadpan accountability partner for macOS.** Holt keeps track of what you
planned, what you're doing, what you finished and — with great precision — what
you didn't. He runs a Pomodoro timer in your menu bar, watches which apps and
sites eat your day, and tells you about it through macOS notifications, with
the warmth of a stapler.

> "Session complete. No collapse into digital nonsense. Growth."

Everything stays on your Mac: one local SQLite database, no account, no cloud.

## Status

Early development — **milestone M0** (foundations). What works today:

- Menu bar timer: deep work, short/long breaks, pause/resume, take break, end
  session, end break → next session ready.
- Long break after every 4 completed sessions; ending early never counts.
- Tone slider (Polite ↔ Punchy ↔ Strict) that changes Holt's wording.
- Completion sound + notification with a Holt line.
- Main window with the timer hero and a placeholder climbing animation.

The full product is specified in [docs/PRODUCT_SPEC.md](docs/PRODUCT_SPEC.md);
the build plan and milestones are in [docs/PLAN.md](docs/PLAN.md).

## Install a CI build

Every push to `main` is built by GitHub Actions. Open the latest successful
[CI run](../../actions/workflows/ci.yml), download the `Holt-…` artifact, unzip,
open `Holt.dmg` and drag Holt to Applications.

Builds are **not notarized** (no Apple Developer ID yet), so macOS blocks the
first launch. Either:

- open **System Settings → Privacy & Security** and click **Open Anyway**, or
- run `xattr -dr com.apple.quarantine /Applications/Holt.app`.

Requires macOS 14 or later on Apple Silicon. Liquid Glass styling appears on
macOS 26.

## Build from source

```bash
swift test                # logic tests (HoltCore)
scripts/bundle-app.sh     # builds and ad-hoc signs dist/Holt.app
scripts/make-dmg.sh       # dist/Holt.dmg
```

Needs Xcode 26 (Swift 6.2). CI is the reference build machine — see
[.github/workflows/ci.yml](.github/workflows/ci.yml).

### Optional: stable signing in CI

macOS ties permissions (Accessibility, Screen Recording, Automation) to the
app's signature. Ad-hoc signatures change on every build, so each update asks
again. To avoid that without a paid Developer ID, add a self-signed
code-signing certificate as repository secrets `MACOS_CERT_P12` (base64 of the
`.p12`) and `MACOS_CERT_PASSWORD`; CI then signs with it automatically.

## Project layout

```
Sources/HoltCore   all product logic (no UI) — session engine, voice, …
Sources/Holt       the SwiftUI menu bar app
Tests/             swift-testing tests for HoltCore
Resources/         Info.plist, entitlements
scripts/           bundle, DMG, CI signing
docs/              product spec and engineering plan
```

## About the persona

Holt is an original character: a stoic, precise, by-the-book captain type with
a dry sense of humour. All of his lines are written for this project.
