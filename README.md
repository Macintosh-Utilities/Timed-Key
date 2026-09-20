<div align="center">

<picture>
  <img src="Brand/timed-key-readme-banner.svg" width="100%" alt="Timed Key — the right key, the right app, exactly on time">
</picture>

# ⌨️ Timed Key

**A focused, native macOS automation utility built for dependable keyboard scheduling.**

<p>
  <img alt="macOS 14 or later" src="https://img.shields.io/badge/macOS-14%2B-F5F7F4?style=for-the-badge&logo=apple&logoColor=080A0B&labelColor=080A0B">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/architecture-arm64-CCFF00?style=for-the-badge&logo=apple&logoColor=CCFF00&labelColor=080A0B">
</p>

<p>
  <img alt="SwiftUI" src="https://img.shields.io/badge/SwiftUI-native-F05138?style=flat-square&logo=swift&logoColor=white">
  <img alt="Hardened Runtime" src="https://img.shields.io/badge/Hardened%20Runtime-enabled-2EA44F?style=flat-square">
  <img alt="Signing" src="https://img.shields.io/badge/signing-Apple%20Development-F5A623?style=flat-square">
  <img alt="License MIT" src="https://img.shields.io/badge/license-MIT-3B82F6?style=flat-square">
</p>

[What it does](#-what-it-does) · [Install](#-install-timed-key) · [First launch](#-first-launch--gatekeeper) · [Use it](#-the-focused-scheduling-flow) · [Reliability](#-reliability-by-design) · [Build](#-building-from-source) · [Patch notes](PATCH_NOTES.md)

</div>

---

> [!NOTE]
> **Timed Key combines a focused experience with a reliability-first scheduling engine.** The **When → Key → App** flow supports multiple schedules, repeat rules, exact-second delivery, permission diagnostics, verified LaunchAgents, persistent outcomes, and recoverable failures.

<table>
  <tr>
    <td width="25%" align="center">
      <h3>🗓️ Visual</h3>
      <p>Pick a date and exact time from native controls—or type it directly.</p>
    </td>
    <td width="25%" align="center">
      <h3>⚡ Precise</h3>
      <p>Complete the final wait in-app for exact-second delivery.</p>
    </td>
    <td width="25%" align="center">
      <h3>🧭 Focused</h3>
      <p>Move naturally through the clear When → Key → App flow.</p>
    </td>
    <td width="25%" align="center">
      <h3>💚 Visible</h3>
      <p>See permissions, scheduler health, and the last result at a glance.</p>
    </td>
  </tr>
</table>

<p align="center"><sub>OBSIDIAN INTERFACE &nbsp;◆&nbsp; ELECTRIC-LIME ACTIONS &nbsp;◆&nbsp; NATIVE SWIFTUI</sub></p>

## ✨ What it does

Timed Key sends a selected keyboard key to a selected macOS application at a scheduled date and exact time—even when the target app is not already open.

| | Choose | Available options |
|:--:|---|---|
| 🗓️ | **When** | Native calendar, visual hour/minute/second controls, or manual `HH:MM:SS` entry |
| 🔁 | **Repeat** | One Time, Daily, Weekdays, Weekends, or Weekly |
| ⌨️ | **Key** | Common controls, arrows, A–Z, 0–9, and F1–F5 |
| 🎯 | **App** | A running application or an exact manually entered target |

### Highlights

- **Focused native interface** built around a clear When → Key → App sequence.
- **Exact-second scheduling** layered on top of launchd's minute-resolution calendar triggers.
- **Multiple independent schedules** with pause, resume, retry, and delete controls.
- **Verified app targeting** by display name, bundle identifier, and exact application path.
- **Visible reliability diagnostics** for permissions, installation, scheduler health, and the last run.
- **Persistent outcomes** for success, failure, deferred delivery, missed runs, and measured timing drift.
- **Automatic repair** for stale scheduler configuration and orphaned LaunchAgents.
- **Recoverable one-time failures** retained in the queue with a visible **Retry** action.
- **Apple Silicon-only output** with the Xcode target explicitly restricted to `arm64`.

---

## 📋 Requirements

| Requirement | Value |
|---|---|
| **Mac** | Apple Silicon (`arm64`) |
| **macOS** | 14.0 Sonoma or later |
| **Install location** | `/Applications` or `~/Applications` |
| **Permissions** | Accessibility and CoreGraphics PostEvent access |
| **Session** | An active signed-in Aqua user session at delivery time |
| **Network** | Not required for normal operation |

> [!IMPORTANT]
> The downloadable development build is signed with **Apple Development**, not **Developer ID Application**, and is not notarized for public distribution. Gatekeeper may therefore block the first launch until the user explicitly approves the app. Read the first-launch instructions below before opening it.

---

## 📦 Install Timed Key

1. Download and extract `Timed Key.app` from the official Macintosh Utilities GitHub release.
2. Drag **Timed Key.app** into `/Applications`.
3. Open the copy inside **Applications**—do not repeatedly launch a copy from Downloads, a mounted archive, or Xcode DerivedData.
4. Complete the Gatekeeper approval described below if macOS blocks the first launch.
5. Open Timed Key's **Reliability** panel and select **Grant access**.
6. Approve the requested macOS privacy permission, then quit and reopen Timed Key.

Using a stable Applications-directory copy matters: each schedule stores an exact application path so launchd consistently starts the same signed build.

---

## 🛡 First launch & Gatekeeper

Because this release uses an **Apple Development** signature instead of a notarized Developer ID distribution signature, a Mac that downloaded it from the internet may show one of these first-launch alerts:

- **“Apple cannot check ‘Timed Key’ for malicious software.”**
- **“The developer of ‘Timed Key’ cannot be verified.”**
- A similar message saying Timed Key cannot be opened because Apple cannot verify the developer.

The buttons can vary by macOS version. The initial dialog may offer **Done**, **Cancel**, or **Move to Trash** without showing an **Open** button.

### Approve the expected verification warning

> [!WARNING]
> Only continue if you intentionally downloaded Timed Key from the official Macintosh Utilities repository and the archive has not been replaced or modified. A Gatekeeper override tells macOS to trust this specific app despite the missing Developer ID notarization.

1. Double-click **Timed Key.app** once so macOS records the blocked launch.
2. Dismiss the warning with **Done** or **Cancel**. Do not choose **Move to Trash** if this is the expected official download.
3. Open **Apple menu → System Settings → Privacy & Security**.
4. Scroll down to the **Security** section.
5. Find the message explaining that Timed Key was blocked.
6. Click **Open Anyway**. Apple makes this control available for approximately one hour after the blocked launch attempt.
7. Authenticate with Touch ID or your Mac login password if requested.
8. When the warning returns, click **Open** to confirm.

macOS saves the app as an exception, so subsequent launches of that exact copy should work normally. Replacing, moving, rebuilding, or differently signing the app can cause macOS or its privacy system to ask again.

Apple's current instructions are available in [Safely open apps on your Mac](https://support.apple.com/102445).

> [!NOTE]
> **Open Anyway only overrides Gatekeeper's first-launch policy.** It cannot repair an invalid or expired signature, and it cannot make a development provisioning profile valid for an unregistered Mac. If the exported app contains a profile limited to registered testing Macs, the recipient's Mac must be registered and included when the build is signed. See Apple's [registered-device distribution guide](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices).

### Alerts you should **not** bypass

Stop and obtain a fresh copy if macOS says that Timed Key:

- **will damage your computer**;
- **contains malware**; or
- **is damaged** and cannot be opened.

Those messages are different from the expected developer-verification warning and can indicate corruption, modification, a revoked authorization, or a genuinely unsafe file. Do not disable Gatekeeper globally, and do not use Terminal commands that remove quarantine metadata to force the app open.

<details>
<summary><strong>Why does this warning appear?</strong></summary>

For software distributed outside the Mac App Store, Gatekeeper expects a **Developer ID Application** signature and normally expects notarization. **Apple Development** signing is intended for development and controlled testing. It authenticates a development build but is not the public-distribution identity Gatekeeper expects.

This warning does not mean macOS detected malware; it means Apple cannot apply the normal Developer ID and notarization assurances. Users should still verify that the download came from the expected source before overriding the warning.

</details>

---

## 🔐 Accessibility permission

After Gatekeeper allows the app to launch, macOS must separately authorize Timed Key to send keyboard events to other applications.

1. Open Timed Key.
2. In **Reliability**, click **Grant access**.
3. When macOS opens **System Settings → Privacy & Security**, enable Timed Key under **Accessibility** or the corresponding device-control section shown by your macOS version.
4. Authenticate if macOS requests it.
5. Quit and reopen Timed Key if the status does not immediately refresh.

The healthy state is:

```text
Permissions      PASS
Stable install   PASS
Scheduler        PASS
```

> [!IMPORTANT]
> Timed Key cannot silently grant protected input-control permission to itself. This is an intentional macOS security boundary, not an app failure.

---

## 🎛 The focused scheduling flow

### ① Choose when

Select a date from the graphical calendar, then choose the hour, minute, and second. For direct entry, expand **Type HH:MM:SS instead** and enter a 24-hour value such as `09:30:05`.

The visual controls and typed value remain synchronized.

### ② Choose a repeat rule

| Rule | Behavior |
|---|---|
| **One Time** | Runs once on the selected calendar date |
| **Daily** | Runs every day after the selected start date |
| **Weekdays** | Runs Monday through Friday |
| **Weekends** | Runs Saturday and Sunday |
| **Weekly** | Runs on the selected weekday |

### ③ Choose a key

Timed Key supports:

- Return, Tab, Space, Delete, and Escape
- Left, Right, Up, and Down Arrow
- Letters A–Z
- Digits 0–9
- Function keys F1–F5

### ④ Choose an application

Choose a running application from the menu. Timed Key records its display name, bundle identifier, and exact bundle path when available. Select **Other…** to enter an application name manually.

### ⑤ Add the schedule

Click **Add Schedule**. Timed Key persists the schedule before registering its LaunchAgent, verifies that launchd retained it, and displays the next scheduled press at the top of the window.

Each queue item can be paused, resumed, retried when applicable, or deleted.

---

## 💚 Reliability by design

The Reliability panel reports four independent signals:

| Signal | What it verifies |
|---|---|
| **Permissions** | Accessibility and CoreGraphics PostEvent authorization |
| **Stable install** | Scheduling is using a stable Applications-directory copy |
| **Scheduler** | Every enabled schedule has a matching, loaded LaunchAgent |
| **Last run** | The most recently persisted success, failure, deferred, or missed result |

If the app is moved, replaced, or an agent becomes inconsistent, select **Repair**. Timed Key also reconciles saved schedules automatically at launch.

### Late, locked, and failed runs

- Recurring runs have a bounded 15-minute late window; older launches are recorded as missed.
- One-time runs may recover later on their selected day but never execute on another calendar day.
- If the screen is locked, Timed Key waits up to five minutes for an unlock.
- Transient application launch and activation failures are retried.
- Failed one-time schedules remain visible, disabled, and retryable.
- Successful one-time schedules are removed from saved state and unloaded from launchd.
- Failed and missed helpers exit with a nonzero process status.

No macOS utility can guarantee delivery through shutdown, power loss, hardware failure, a terminated login session, revoked permission, or a target application that refuses keyboard input. Timed Key explicitly records controllable failures instead of silently claiming success.

---

<details>
<summary><strong>⚙️ How exact scheduling works</strong></summary>

Every enabled schedule receives a unique per-user LaunchAgent:

```text
~/Library/LaunchAgents/com.timedkey.trigger.<schedule-uuid>.plist
```

The agent starts a fresh background Timed Key instance using `/usr/bin/open -W -n` and passes the exact installed app path plus strictly validated schedule arguments.

Because `StartCalendarInterval` has minute-level precision, the scheduled helper performs the final exact-second wait itself. At delivery time it:

1. Validates the schedule UUID, key code, time, start date, repeat mode, and app identity.
2. Reconstructs and verifies the expected occurrence.
3. Waits until the requested second using short absolute-time checks.
4. Rejects launches that are too early, stale, or on the wrong recurrence day.
5. Checks Accessibility and PostEvent permission.
6. Detects whether the Mac is locked and waits for an unlock when appropriate.
7. Resolves and launches the target app.
8. Repeatedly activates it and verifies that it is genuinely frontmost.
9. Posts a key-down and key-up pair.
10. Persists the outcome and measured timing drift.
11. Cleans up a completed one-time schedule only after verified success.

The app never reports success merely because a timer fired or a process launched.

</details>

<details>
<summary><strong>🧾 Persistence and diagnostics</strong></summary>

Schedules and the latest run record live in the app's macOS preferences domain. A cross-process file lock protects writes from the foreground app and scheduled helper.

```text
timedKey.multipleSchedules.v2
timedKey.lastRun.v1
```

Compatible version 1 schedules are migrated when possible. Scheduled-run diagnostics are written to:

```text
~/Library/Logs/Timed Key/scheduled-fire.log
```

The log uses owner-only `0600` permissions and records target time, release time, measured drift, and the final result.

</details>

---

## 🛠 Building from source

1. Clone the repository.
2. Open `Timed Key.xcodeproj` in the full Xcode application.
3. Select your Apple Development team under **Signing & Capabilities**.
4. Keep **App Sandbox** disabled; Timed Key must manage the user's LaunchAgents and synthesize input after explicit approval.
5. Build the **Timed Key** scheme with `⌘B`.

### Command-line Release build

```sh
xcodebuild \
  -project 'Timed Key.xcodeproj' \
  -scheme 'Timed Key' \
  -configuration Release \
  -derivedDataPath build/DerivedData \
  CODE_SIGN_STYLE=Automatic \
  clean build
```

If the full Xcode installation is not the active developer directory, set `DEVELOPER_DIR` explicitly:

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

The product is generated at:

```text
build/DerivedData/Build/Products/Release/Timed Key.app
```

### Verify the build

Run the built-in deterministic recurrence and parser suite:

```sh
'build/DerivedData/Build/Products/Release/Timed Key.app/Contents/MacOS/Timed Key' --self-test
```

Verify the code signature:

```sh
codesign --verify --deep --strict --verbose=2 \
  'build/DerivedData/Build/Products/Release/Timed Key.app'
```

Verify that the executable is Apple Silicon-only:

```sh
lipo -archs \
  'build/DerivedData/Build/Products/Release/Timed Key.app/Contents/MacOS/Timed Key'
```

Expected result:

```text
arm64
```

Build success is not treated as proof of scheduled delivery. Before shipping, create a real one-time schedule and confirm the banner, foreground application, key submission, persisted success, timing log, queue cleanup, and LaunchAgent cleanup.

---

## 🔩 Xcode configuration

| Setting | Effective value |
|---|---|
| Bundle identifier | `Mac-Utilities.Timed-Key` |
| Minimum macOS version | `14.0` |
| Architectures | `arm64` only |
| Code-sign identity | Apple Development |
| Code-sign style | Automatic |
| Hardened Runtime | Enabled |
| App Sandbox | Disabled |
| Release base-entitlement injection | Disabled |

The project explicitly disables unused Apple Events, microphone, camera, contacts, calendars, location, and photo-library access. Hardened Runtime exceptions for JIT, unsigned executable memory, DYLD environment variables, debugging, executable-page protection, and library validation are also disabled.

---

## 📚 Release documentation

- Read the complete [release patch notes](PATCH_NOTES.md).
- Read the prepared [commit notes](COMMIT_NOTES.md).
- Review the [MIT license](LICENSE).

---

<div align="center">

### Built by Macintosh Utilities

**Precise tools for the Mac you already know.**

Made with `SwiftUI` · powered by `launchd` · finished with ⌨️ + ☕️

</div>
