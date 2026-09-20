# Timed Key

Timed Key is a native macOS utility that sends a selected keyboard key to a selected application at a scheduled date and exact time.

Version 2.0 is a complete redesign and reliability overhaul. It replaces the original single-timer experience with a focused **When → Key → App** workflow, multiple schedules, repeat rules, permission diagnostics, stable LaunchAgent management, persistent run results, and recoverable failures.

See [`PATCH_NOTES.md`](PATCH_NOTES.md) for the complete version 2.0 release notes.

## Version 2.0 at a glance

- Native SwiftUI interface designed specifically for macOS.
- Graphical calendar plus visual hour, minute, and second controls.
- Optional manual `HH:MM:SS` entry for precise typing.
- One-time, daily, weekdays, weekends, and weekly schedules.
- Multiple independently managed schedules.
- Exact-second delivery on top of launchd's minute-level scheduling.
- Exact target-app matching by bundle identifier and application path.
- Built-in permission, installation, scheduler, and last-run diagnostics.
- Persistent success, failure, deferred, and missed-run records.
- Automatic scheduler repair and orphan cleanup.
- Recoverable one-time failures with a visible **Retry** action.
- Signed Release build with Hardened Runtime enabled.

## Requirements

- macOS 14.0 or later.
- A signed copy of Timed Key in `/Applications` or `~/Applications`.
- Accessibility and event-posting permission granted by the signed-in user.
- An active macOS Aqua user session at delivery time.

Timed Key does not require a network connection, online account, or cloud service.

## Installation

1. Build or obtain `Timed Key.app`.
2. Place the app at `/Applications/Timed Key.app` for normal use.
3. Open that installed copy rather than repeatedly launching copies from Xcode DerivedData.
4. In the **Reliability** panel, click **Grant access**.
5. Enable Timed Key when macOS opens **System Settings → Privacy & Security**. Depending on the macOS version, the relevant page may be named **Accessibility** or **Device Control and Data Access**.
6. Quit and reopen Timed Key if the permission row does not immediately change to **PASS**.

The Reliability panel should show:

```text
Permissions      PASS
Stable install   PASS
Scheduler        PASS
```

macOS intentionally requires the user to approve input-control permission. Timed Key cannot silently grant this permission to itself.

## Using Timed Key

### 1. Choose when

Select a date from the graphical calendar, then choose the hour, minute, and second.

If you prefer typing, expand **Type HH:MM:SS instead** and enter a 24-hour time such as:

```text
09:30:05
```

The typed value and visual time controls remain synchronized.

### 2. Choose a repeat rule

Available repeat modes are:

- **One Time** — runs once on the selected date.
- **Daily** — runs every day after the selected start date.
- **Weekdays** — runs Monday through Friday.
- **Weekends** — runs Saturday and Sunday.
- **Weekly** — runs on the selected weekday.

### 3. Choose a key

Timed Key currently supports:

- Return, Tab, Space, Delete, and Escape.
- Left, Right, Up, and Down Arrow.
- Letters A–Z.
- Digits 0–9.
- Function keys F1–F5.

### 4. Choose an application

Choose a running application from the menu. Timed Key records the app's display name, bundle identifier, and exact bundle path when available.

Use **Other…** to enter an exact application name manually.

### 5. Add the schedule

Click **Add Schedule**. Timed Key persists the schedule before registering its LaunchAgent, verifies that launchd retained it, and displays the next scheduled press at the top of the window.

Each queue item can be paused, resumed, retried when applicable, or deleted.

## Reliability panel

The Reliability panel reports four independent states:

- **Permissions** — Accessibility and CoreGraphics PostEvent authorization.
- **Stable install** — whether scheduling can use a stable Applications-directory copy.
- **Scheduler** — whether every enabled schedule has a matching loaded LaunchAgent.
- **Last run** — the most recently persisted success, failure, deferred, or missed result.

If the app is moved, replaced, or an agent becomes inconsistent, use **Repair**. Timed Key also reconciles saved schedules automatically when the app starts.

## How scheduling works

Every enabled schedule receives a unique per-user LaunchAgent:

```text
~/Library/LaunchAgents/com.timedkey.trigger.<schedule-uuid>.plist
```

The agent starts a fresh background Timed Key instance through `/usr/bin/open -W -n` and passes the exact installed app path and strictly validated schedule arguments.

Because `StartCalendarInterval` has minute-level precision, the scheduled helper performs the final exact-second wait itself. At delivery time it:

1. Validates the schedule UUID, key code, hour, minute, second, start date, repeat mode, app identity, and optional bundle path.
2. Reconstructs and verifies the expected occurrence.
3. Waits until the requested second using repeated short absolute-time checks.
4. Rejects launches that are too early, stale, or on the wrong recurrence day.
5. Checks Accessibility and PostEvent permission.
6. Detects whether the Mac is locked.
7. Waits up to five minutes for an unlock when delivery is temporarily blocked by the lock screen.
8. Resolves and launches the target application.
9. Waits for that application to finish launching.
10. Repeatedly activates it and verifies that it is genuinely frontmost.
11. Posts a key-down and key-up pair.
12. Keeps the signed helper alive briefly so WindowServer and TCC can finish event attribution.
13. Persists the result and measured timing drift.
14. Cleans up a completed one-time schedule only after verified success.

The app never reports a successful delivery merely because a timer fired or a process launched.

## Late, locked, and failed runs

- A recurring run can be accepted within a bounded 15-minute late window. Older recurring launches are recorded as missed instead of sending an unexpectedly late key.
- A one-time run can recover later on its selected day, but it will not execute on a different calendar day.
- If the screen is locked, Timed Key waits for an unlock for up to five minutes.
- Transient launch and activation failures are retried.
- A failed one-time schedule is disabled and retained in the queue with its reason and a **Retry** action.
- A successful one-time schedule is removed from saved state and unloaded from launchd.
- Failed and missed helpers return a nonzero process status.

No macOS utility can guarantee delivery during power loss, shutdown, a terminated login session, revoked permission, hardware failure, or an application that refuses keyboard input. Timed Key handles the controllable failure paths explicitly and records an outcome instead of silently claiming success.

## Persistence and diagnostics

Schedules and the most recent run record are stored in the app's macOS preferences domain. Writes are protected by a cross-process file lock so the foreground app and scheduled background helper cannot overwrite one another.

Version 2 uses:

```text
timedKey.multipleSchedules.v2
timedKey.lastRun.v1
```

Compatible version 1 schedule data is migrated when possible. The old single LaunchAgent is removed during reconciliation.

Scheduled-run diagnostics are appended directly by the signed helper to:

```text
~/Library/Logs/Timed Key/scheduled-fire.log
```

The log is forced to owner-only `0600` permissions and contains entries such as:

```text
[Timed Key] target=2026-09-20T03:02:33.000Z released=2026-09-20T03:02:33.003Z drift=+0.003s
[Timed Key] 2026-09-20T03:02:34.894Z Escape was submitted to Calculator.
```

## Building from source

Open `Timed Key.xcodeproj` in the full Xcode application, select a valid development team if needed, and build the **Timed Key** scheme.

Command-line Release build:

```sh
xcodebuild \
  -project 'Timed Key.xcodeproj' \
  -scheme 'Timed Key' \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_STYLE=Automatic \
  clean build
```

If the full Xcode installation is not the active developer directory, set `DEVELOPER_DIR` explicitly. For this checkout's external Xcode installation:

```sh
DEVELOPER_DIR='/Volumes/Crucial X9/Xcode.app/Contents/Developer' \
  xcodebuild \
  -project 'Timed Key.xcodeproj' \
  -scheme 'Timed Key' \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_STYLE=Automatic \
  clean build
```

The Release product is generated at:

```text
build/DerivedData/Build/Products/Release/Timed Key.app
```

For reliable scheduling, copy that signed product to `/Applications/Timed Key.app` and consistently use the installed copy.

## Built-in verification

Run the deterministic recurrence and trigger-parser suite without opening the main interface:

```sh
'build/DerivedData/Build/Products/Release/Timed Key.app/Contents/MacOS/Timed Key' --self-test
```

The suite verifies weekday and weekend selection, weekly recurrence, one-time expiration, and strict scheduled-trigger parsing.

Before shipping a build, also verify the signature:

```sh
codesign --verify --deep --strict --verbose=2 \
  'build/DerivedData/Build/Products/Release/Timed Key.app'
```

Build success alone is not treated as proof of scheduled delivery. A release should also be tested with a real one-time schedule while confirming:

- the top-center delivery banner appeared;
- the target application became frontmost;
- the key was submitted;
- the Reliability panel recorded **SUCCESS**;
- timing drift was written to the log;
- the one-time schedule disappeared from the queue;
- the corresponding LaunchAgent was unloaded and removed.

## Xcode project configuration

Version 2.0 updates `Timed Key.xcodeproj/project.pbxproj` as part of the release. The effective Release configuration is:

```text
Bundle identifier:               Mac-Utilities.Timed-Key
Marketing version:               2.0
Build number:                    3
Minimum macOS version:           14.0
Code-sign identity:              Apple Development
Code-sign style:                 Automatic
Development team:                883SQQ4WN6
Hardened Runtime:                Enabled
App Sandbox:                     Disabled
Release base-entitlement inject: Disabled
```

App Sandbox is intentionally disabled. Timed Key must manage the user's LaunchAgents and, after explicit approval, synthesize keyboard input.

The project explicitly disables unneeded access to Apple Events, the microphone, camera, contacts, calendars, location, and the photo library. Hardened Runtime exceptions for JIT, unsigned executable memory, DYLD environment variables, debugging, executable-page protection, and library validation are also explicitly disabled.

## Source layout

- `ContentView.swift` — focused scheduling UI, queue, diagnostics, app picker, permission actions, and transactional schedule changes.
- `KeyCodes.swift` — supported key names and macOS virtual key codes.
- `KeyEventSender.swift` — permission checks, direct diagnostic logging, target resolution, activation verification, and key delivery.
- `ScheduleModels.swift` — schedule and run models, recurrence calculation, migration, persistence, and cross-process locking.
- `SchedulerService.swift` — stable installation, LaunchAgent generation, verification, repair, reconciliation, and cleanup.
- `Theme.swift` — obsidian/lime design tokens and reusable card styling.
- `TimedKeyApp.swift` — foreground and headless launch modes, exact timing, recovery, run recording, cleanup, and self-tests.
