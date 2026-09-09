# Presence — design

Date: 2026-09-08
Status: approved, ready for implementation plan

## Problem

Microsoft Teams on macOS changes status to "Away" (yellow) when the system
goes idle. The goal is to keep the status at "Available" (green) during work
hours, without relying on manually moving the mouse.

Teams determines idleness from the system idle counter (`HIDIdleTime`,
exposed by `IOHIDSystem`) and from screen lock/screensaver state. Any
solution needs to keep this counter low.

## Decisions made

| Decision | Choice |
|---|---|
| Format | macOS menu bar app |
| Trigger | Always active while on, with optional auto-off |
| Screen | Screen stays on and unlocked while active |
| Technique | Hybrid with verification: power assertion first, synthetic input as fallback |

Accepted side effect: while active, there's no screensaver or automatic lock.
Manual locking still works normally.

## Verification (completed on 2026-09-08)

The central premise — that `IOPMAssertionDeclareUserActivity` zeroes out
`HIDIdleTime` — **is false on this machine**.

Two independent measurements, the second with the project's own
`idle-probe` (2026-09-09), over an 858-second window of real idleness —
without the human-input contamination that invalidated the first attempt
during design:

```
caffeinate -u   (2026-09-08):  idle BEFORE =  63.7s | AFTER =  70.0s
idle-probe      (2026-09-09):  idle BEFORE = 857.8s | AFTER = 858.8s
```

The counter didn't drop in either case: it kept climbing. No `caffeinate`
flag solves Teams' problem — the others (`-d`, `-i`, `-s`, `-m`) only prevent
sleep, without touching the idle counter.

**Consequences:**

1. `.synthetic` (F15 key) is the normal mode of operation, not the fallback.
   Accessibility permission is mandatory.
2. The power assertion **is still called on every cycle**. It doesn't zero
   out the counter, but it's what keeps the screen on and unlocked — and a
   locked screen leaves Teams yellow regardless. The two mechanisms are
   complementary, not alternatives.
3. The verified mode is persisted (`Preferences.startMode`). Starting every
   session in `.declared` would waste ~90s rediscovering what's already
   known, with the status exposed during that window.

The architecture absorbed the result without a rewrite — that was the point
of treating verification as part of the product.

## Approach

The app declares user activity via IOKit
(`IOPMAssertionDeclareUserActivity` with `kIOPMUserActiveLocal`) and
**verifies the result** by reading `HIDIdleTime`. The declaration requires no
macOS permission and doesn't inject input, but there's no documented
guarantee that it zeroes out the counter Teams observes.

If verification shows the counter still climbing, the app escalates to
synthetic input (`CGEvent` for the F15 key — nonexistent on Mac keyboards, no
app reacts to it), which reliably zeroes out the counter but requires
Accessibility permission.

The synthetic event is posted to `.cghidEventTap`, not `.cgSessionEventTap`.
Events injected into the session tap may not reach `IOHIDSystem` and
therefore may not reset the counter — which would defeat the fallback
entirely.

Privilege order: the permission-free path is always tried first; permission
is only requested once it's proven necessary.

### Known limit of the verification

While the user is actually using the Mac, `HIDIdleTime` stays near zero
because of human input, and the reading can't distinguish "the assertion
worked" from "they moved the mouse." Verification is only informative during
windows of real idleness — which are exactly the windows the app needs to
act in. The state shown in the menu says "the counter is low," not "the
assertion is working"; the spec doesn't promise more than that.

## Platform and distribution

- **macOS 14+**, arm64. `MenuBarExtra` and `SMAppService` require macOS 13+;
  14 is the floor adopted to avoid APIs still in transition.
- **App Sandbox off.** Access to `IOHIDSystem` and `CGEvent.post` aren't
  possible under sandbox. The app isn't distributed through the App Store.
- **Code signing.** Accessibility permission is tied by TCC to the bundle ID
  *and* to the binary's signature. With an ad-hoc signature, every rebuild
  produces a new cdhash and macOS revokes the granted permission — the app
  goes back to asking for authorization on every build. Two ways out:
  1. Sign with a stable Developer ID certificate, when one is available.
  2. Accept re-granting the permission on every build during development, and
     sign ad-hoc just once for the final installed version.

  The implementation plan adopts (2) by default and leaves (1) as a one-line
  configuration in the build script. The bundle ID is fixed:
  `com.rootless.presence`.
- **Installation.** The build script produces `Presence.app`; an `install`
  target copies it to `/Applications`. `SMAppService.mainApp` requires the
  app to be in a stable location — registering the login item from the build
  folder produces a broken item as soon as that folder changes.

## Architecture

```
PresenceApp (SwiftUI, MenuBarExtra, LSUIElement)
   └── PresenceController      — state machine, @MainActor
         ├── ActivityDeclarer  — IOPMAssertionDeclareUserActivity
         ├── IdleReader        — HIDIdleTime via IOHIDSystem (direct IOKit)
         ├── SyntheticInput    — CGEvent F15 on .cghidEventTap (fallback)
         ├── LockMonitor       — screen lock/unlock notifications
         └── Preferences       — UserDefaults
```

Build: Swift Package Manager + a packaging script for the `.app`. No Xcode
project, to keep everything in version-controllable text. Swift 6.3
toolchain, with the package in language mode 5: IOKit's C APIs and
`DistributedNotificationCenter` callbacks generate considerable friction
under strict concurrency, with no real benefit for a single-process,
single-thread app. `PresenceController` is `@MainActor` and the UI observes
its published state.

### Components

**IdleReader** — reads `HIDIdleTime` from the `IOHIDSystem` service via IOKit
and returns seconds. No shelling out to `ioreg`. Single dependency: IOKit.

**ActivityDeclarer** — wraps `IOPMAssertionDeclareUserActivity`, keeping the
`IOPMAssertionID` across calls to reuse the assertion. Reports failure
instead of swallowing it.

**SyntheticInput** — posts F15 key down + key up (`kVK_F15`, code 0x71) via
`CGEvent` on `.cghidEventTap`. Exposes a query of the permission state
(`AXIsProcessTrusted`) and an action that opens the corresponding Settings
pane. The permission is re-queried every cycle, so granting authorization
while the app is open takes effect without a restart.

**LockMonitor** — observes `com.apple.screenIsLocked` and
`com.apple.screenIsUnlocked` on `DistributedNotificationCenter`.

**Preferences** — persists the auto-off interval and the launch-at-login
preference in `UserDefaults`. The on/off state is **not** persisted: the app
always starts off.

**PresenceController** — orchestrates the loop, holds the state and
publishes it to the UI. Receives its dependencies via protocol, to allow
substitutes in tests.

## States

| State | Meaning |
|---|---|
| `off` | Toggle off. No action. |
| `active(.declared)` | Loop running via power assertion, no permissions. |
| `active(.synthetic)` | Loop running with synthetic input, after escalation. |
| `blocked` | Escalation needed, but Accessibility permission was denied. The app can't fulfill its function and says so. |
| `pausedLocked` | Screen locked. Toggle stays on, loop suspended. |

## Main loop

Runs every 30 seconds while on and not paused:

1. `ActivityDeclarer.declare()` (always, in both modes)
2. In `.synthetic`, also `SyntheticInput.tap()`
3. Waits 1 second
4. Reads `IdleReader.seconds()`
5. Idle < 5s → failure counter reset to zero
6. Idle >= 5s for 3 consecutive cycles → escalates to `.synthetic`; if
   permission is denied, goes to `blocked`

Safety margin: Teams marks you away after around 5 minutes of idleness. A
30s cycle with escalation after 3 failures takes at most ~93s to correct the
mode — well within that window. The numbers aren't arbitrary.

**App Nap.** A background `LSUIElement` app suffers timer coalescing, and a
large delay in the loop would break the guarantee above. The loop is a
`Task` with `Task.sleep` between cycles, and the app holds a
`ProcessInfo.beginActivity(options: .userInitiated)` while active — it's
`beginActivity` that prevents deferral, not the timer type.

## Interface

Menu bar:

- **Enable** / **Disable** — main toggle
- **State** — `Active · idle 2s`, `Active (extended mode)`,
  `Paused (screen locked)`, `Needs permission`, or `Off`. The idle value
  updates live and serves as visible evidence.
- **Grant Accessibility permission** — visible only in `blocked`; opens the
  Settings pane.
- **Auto-off after** — Never / 1h / 4h / 8h (default: 8h)
- **Launch at login** — via `SMAppService`
- **Quit**

The menu bar icon is a filled circle when active, outlined when off, and
with a diagonal bar in `blocked`. Template icon, to follow light and dark
themes.

All diagnostics also go to `OSLog` (subsystem `com.rootless.presence`), to
investigate a "why did it turn yellow at 3pm" after the fact.

## Errors and edge cases

- **Assertion fails** (IOKit error) → escalates immediately, without waiting
  for the 3 cycles. The app never reports "active" without having verified
  it.
- **Permission denied** → `blocked` state, with a button that opens
  Settings. The app doesn't pretend to be working.
- **Screen locked manually** → `pausedLocked`. Without this, declaring
  activity would wake the display, leaving the Mac lit up all night after
  the user leaves. With the screen locked, Teams marks you away regardless,
  so the pause costs nothing. On unlock, the loop resumes on its own — the
  toggle was never turned off.
- **Mac sleep** (lid closed or manual sleep) → the app doesn't try to
  prevent it. On wake, it resumes if still within the auto-off interval.
- **Auto-off** is calculated by wall-clock time: it stores the start `Date`
  and compares it against the present. Counting cycles would mean 3 hours of
  sleep wouldn't count, and the app would stay on well past what was
  intended.
- **Start** → always off. Never turns itself on.

## Tests

- **IdleReader** (integration): confirms the reading returns a plausible
  value (>= 0 and < 24h) and that it grows over 2s with no input. The test
  detects contamination from concurrent human activity (a drop in the
  value) and is marked skip in that case, instead of failing on noise — it
  was exactly this noise that invalidated the initial measurement.
- **PresenceController** (unit, fake dependencies, injected clock): escalates
  to `.synthetic` on the third consecutive reading >= 5s and not on the
  second; resets the counter to zero on a good reading; assertion failure
  escalates immediately; denied permission leads to `blocked`; screen lock
  leads to `pausedLocked` and unlock resumes; auto-off fires by wall-clock
  time, including a clock jump simulating sleep; initial state is `off`.
- **SyntheticInput**: documented manual test — without granted permission,
  `CGEvent.post` fails silently, so an automated test would be a false
  positive.
- **Manual, at the end**: turn on, leave the Mac idle for 15 minutes, confirm
  Teams stays green and that `HIDIdleTime` in the menu stayed low.

## Definition of done — completed on 2026-09-09

1. ✅ **Verification experiment.** Two measurements, the second clean,
   recorded above. The power assertion doesn't zero out `HIDIdleTime`.
2. ✅ **Automated tests.** 37 tests, 0 failures.
3. ✅ **App installed** in `/Applications`, opened by the user.
4. ✅ **End-to-end test.** Over 40 minutes with Teams green, confirmed by the
   user and corroborated by independent sampling of `HIDIdleTime` every 15s:

```
09:09-09:11   16 → 31 → 46 → 6 → 21 → 36 → 51 → 66 → 81 → 96 → 111   (app not yet acting)
09:12:05      0.4                                                     (starts acting)
09:13-09:29   13 → 28 → 10 → 26 → 8 → 23 → 6 → 21 → 4 → 19 → 1 → 16  (sawtooth)
```

The counter never exceeds **31.9s** after stabilizing — exactly the 30s
cycle plus the 1s check. The pattern is mechanical, not human: real use would
keep idle irregular and almost always at zero.

The app stabilized in **`.synthetic`** mode, as the verification predicted.

This is the first direct observation of the central mechanism working. Until
now, the tests proved the logic around F15, not F15 itself.

## Out of scope

Time-based scheduling, Teams API integration, meeting detection, usage
history.
