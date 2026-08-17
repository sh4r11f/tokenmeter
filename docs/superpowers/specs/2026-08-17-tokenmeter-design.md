# TokenMeter — Design Spec

Date: 2026-08-17
Status: Approved

## Purpose

A macOS menu bar app that shows how much of the user's Claude Code
subscription rate limit (5-hour session window and 7-day weekly window)
has been used, and how much is left, at a glance, without opening a
terminal.

## Constraints discovered during research

- Claude Code has no public/documented API to query rate-limit usage
  on demand. It does, however, have an **officially documented
  `statusLine` hook**: a user-configurable command that Claude Code
  invokes with a JSON payload on stdin every time it renders its
  in-terminal status line. That payload includes:

  ```jsonc
  "rate_limits": {             // present for subscribers, after first API response in a session
    "five_hour": { "used_percentage": number, "resets_at": number /* unix epoch seconds */ },
    "seven_day": { "used_percentage": number, "resets_at": number }
  }
  ```

  This was confirmed by inspecting the strings embedded in the
  installed Claude Code binary (`~/.local/share/claude/versions/*`),
  which contains the full statusLine JSON schema documentation used by
  its own `/statusline` setup agent.

- This field is only populated for Claude.ai subscription plans
  (Pro/Max), not API-key/pay-per-token usage — there is no fixed
  "limit" in the latter case, so this is expected, not a gap.
- The hook only fires while a Claude Code session is actively
  rendering. There is no push/pull mechanism for fresh data when no
  session is open. Per product decision below, the app shows the last
  known value and marks it stale rather than trying to estimate
  further.
- No OAuth token extraction, Keychain access, or private endpoint
  reverse-engineering is involved anywhere in this design.

## Product decisions

- **Stale data**: when `status.json` is older than ~2 minutes, the
  menu bar item dims and the dropdown shows "updated Nm ago" instead
  of implying the number is current.
- **Default menu bar label**: always the 5-hour session limit's
  `used_percentage` (switchable to 7-day, or "whichever is more
  urgent," in Preferences).

## Architecture

```
┌─────────────────────────┐   stdin JSON    ┌──────────────────────┐
│ Claude Code session      │ ──────────────▶ │ ~/.claude/tokenmeter/│
│ (any terminal, renders   │                 │ statusline.sh        │
│ its status line)         │ ◀────────────── │                       │
└─────────────────────────┘  status text     └──────────┬───────────┘
                                                          │ writes atomically
                                                          ▼
                                             ┌──────────────────────────┐
                                             │ ~/.claude/tokenmeter/     │
                                             │ status.json               │
                                             └──────────┬────────────────┘
                                                          │ FSEvents watch
                                                          │ (+ 10s poll fallback)
                                                          ▼
                                             ┌──────────────────────────┐
                                             │ TokenMeter.app             │
                                             │  NSStatusItem (MenuBarExtra)│
                                             │  "5h 42%"  ▾                │
                                             └──────────────────────────┘
```

Everything is local. No network calls originate from TokenMeter itself.

## Components

1. **`statusline.sh`** (installed to `~/.claude/tokenmeter/statusline.sh`)
   - Reads stdin JSON (the statusLine payload).
   - Extracts `rate_limits.five_hour` / `rate_limits.seven_day`.
   - Writes `~/.claude/tokenmeter/status.json` atomically (write to
     temp file + `mv`, so the watcher never reads a half-written file).
   - Echoes a short status line back to stdout (`5h: 42% · 7d: 18%`)
     so the terminal status line stays useful — TokenMeter isn't just
     taking over the status line silently.
   - If chained (see `SettingsInstaller` below), first runs the user's
     pre-existing statusLine command and prepends its output.

2. **`SettingsInstaller`** (Swift, `TokenMeterCore`)
   - Reads `~/.claude/settings.json` (resolving a symlink if present).
   - If no `statusLine` key exists: installs ours directly.
   - If one exists and isn't already ours: shows the user the existing
     command and offers to wrap it (call it, then also run our
     extraction) rather than silently overwriting it.
   - Always writes a timestamped backup
     (`~/.claude/tokenmeter/settings.json.bak-<timestamp>`) before
     modifying anything, and preserves all unrelated keys.
   - Exposes an `uninstall()` that restores the most recent backup.

3. **`StatusFileStore`** (Swift, `TokenMeterCore`)
   - Decodes `status.json` into a `RateLimitStatus` model.
   - Computes staleness relative to "now."
   - Pure, side-effect-free parsing — this is the most heavily unit
     tested piece.

4. **Menu bar app** (`TokenMeter` executable target)
   - SwiftUI `MenuBarExtra` scene, `LSUIElement=true` (no Dock icon).
   - `DispatchSource` file watcher on `status.json`, 10s poll as a
     safety net in case the watcher misses an event (e.g. after
     sleep/wake).
   - Label colored by threshold: green <50%, yellow 50–80%, red >80%;
     dimmed when stale.
   - Dropdown: 5h used/remaining % + "resets in Xh Ym"; 7d used/
     remaining % + "resets in Xd Yh"; last-updated timestamp; "Repair
     hook" (re-runs the installer); Preferences (label metric,
     launch-at-login via `SMAppService`); Quit.

## Data flow

Claude Code session renders status line → pipes JSON to
`statusline.sh` → script extracts `rate_limits` → writes `status.json`
atomically → TokenMeter watches the file → updates `NSStatusItem`.

## Error handling

- Malformed/missing JSON on stdin: `statusline.sh` still emits a
  status line (falls back to just running the wrapped command, if
  any) and does not write `status.json` — the app treats a missing
  file as "not installed yet," not an error state.
- `status.json` present but missing `rate_limits` entirely (e.g. API-
  key usage, not a subscription): the app shows "No subscription rate
  limit data" instead of a bogus 0%.
- `settings.json` unreadable/unwritable: installer surfaces a clear
  error in the app UI rather than failing silently, and never deletes
  the original file.

## Testing

- `TokenMeterCoreTests` (XCTest): JSON parsing edge cases (missing
  `rate_limits`, missing `seven_day` only, malformed input),
  percentage/threshold/color mapping, staleness detection,
  `settings.json` merge logic (preserves unrelated keys, handles a
  pre-existing `statusLine`, handles a symlinked settings file,
  backup/restore round-trip).
- `scripts/test-statusline.sh`: pipes fixture JSON payloads into
  `statusline.sh` and asserts on the resulting `status.json`.
- End-to-end manual verification: install the real hook, run a real
  `claude -p` session, confirm the running app's menu bar updates.

## Packaging & repo

- Swift Package Manager (not `.xcodeproj`) so the whole thing builds
  and tests from the CLI (`swift build`, `swift test`) — this matters
  because there's no Xcode GUI in this environment, and it keeps CI
  simple.
- `scripts/build-app.sh` assembles `TokenMeter.app` from the SPM build
  product (binary + `Info.plist` + icon).
- Public GitHub repo `sh4r11f/tokenmeter`, MIT license, README with
  the architecture diagram above plus install/uninstall instructions.

## Out of scope (YAGNI)

- No fallback token-usage estimator from local transcript logs when no
  session is active (rejected during design — can't reconstruct the
  real plan cap from tokens alone, would just be a second, less
  trustworthy number next to the real one).
- No Homebrew tap, no auto-update mechanism, no code signing/
  notarization for this first version.
