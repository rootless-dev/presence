# Presence

[![CI](https://github.com/rootless-dev/presence/actions/workflows/ci.yml/badge.svg)](https://github.com/rootless-dev/presence/actions/workflows/ci.yml)

macOS menu bar app that keeps Microsoft Teams status at **Available** while
it's on.

## The problem

Teams marks you away based on the system idle counter (`HIDIdleTime`, exposed
by `IOHIDSystem`). A few minutes away from the keyboard and the status turns
yellow, even if you're sitting right in front of the computer.

## How it works

Every 30 seconds the app acts and then **checks whether it acted**:

1. Declares user activity via IOKit (`IOPMAssertionDeclareUserActivity`, the
   same API behind `caffeinate -u`).
2. Waits one second and reads `HIDIdleTime` back.
3. If the counter doesn't budge for three consecutive cycles, it escalates to
   injecting a synthetic **F15** key — a key that doesn't exist on Mac
   keyboards and that no application reacts to. This mode requires
   Accessibility permission.

The menu shows the actual idle counter, in seconds. You can see it's working
instead of hoping it is.

### What the measurement showed

The project's initial premise was that the IOKit power assertion would be
enough. It isn't. Two independent measurements, with the machine verifiably
idle:

```
caffeinate -u:  idle 63.7s  →  70.0s
idle-probe:     idle 857.8s →  858.8s
```

The counter kept climbing in both. **Declaring activity does not zero out
`HIDIdleTime`** — no `caffeinate` flag fixes this. That's why the
synthetic-key mode is the normal mode of operation, not the exception.

The assertion is still called every cycle for a different reason: it's what
keeps the screen on and unlocked, and a locked screen leaves Teams yellow
regardless. The two mechanisms are complementary.

Run `make probe` to repeat the measurement on your machine.

## Requirements

- macOS 14 or later (Apple Silicon)
- Xcode with Swift 6.0+ to build
- No external dependencies — only system frameworks

## Installation

```bash
make install
open /Applications/Presence.app
```

In the menu bar icon, click **Enable**. macOS will ask for Accessibility
permission: grant it in System Settings › Privacy & Security ›
Accessibility and enable again. The menu should then show
`Active (extended mode) · idle Ns`.

> Install in `/Applications` before using "Launch at login". `SMAppService`
> stores the bundle path, and a login item registered from the build folder
> breaks when that folder changes.

## Usage

```bash
make test      # runs the test suite
make build     # builds in release
make bundle    # generates Presence.app
make install   # installs to /Applications
make probe     # measures whether the power assertion zeroes the counter on this machine
make clean     # cleans build artifacts
```

## What to expect

- **The screen doesn't dim or lock** while the app is active. That's the
  price of appearing active: if the screen locks, Teams marks you away
  regardless.
- **With the screen locked, the app pauses itself.** Declaring activity would
  wake the display, and nobody wants the Mac lit up all night. It resumes on
  unlock.
- **Lunch break.** In **Lunch break…** (a settings window, any minute of the
  day) you enable it and set the window. Every day in that window the app
  steps aside: it stops declaring activity, the icon turns into a cup, and it
  comes back on its own at the end. Off by default. For the days that don't
  follow the routine, **Pause for** in the menu suspends it right now for 30
  minutes to 2 hours, and **Resume now** cuts any break short — coming back
  early only skips today's window, not tomorrow's.
- **Auto-off** is configurable: never, 1h, 4h, or 8h (default). It counts
  wall-clock time, so hours spent asleep count toward the deadline. Breaks
  don't count: an hour of lunch pushes the deadline an hour further out.
- **The app always starts off.** It never turns itself on.
- **Every rebuild with an ad-hoc signature revokes the Accessibility
  permission**, because macOS ties the permission to the binary's hash. For a
  stable identity: `DEV_ID="Developer ID Application: ..." make bundle`.

## Diagnostics

```bash
log show --predicate 'subsystem == "com.rootless.presence"' --last 1h
```

The log records the transitions that answer "why did the status turn yellow
at 3pm": when it turned on and in which mode, when it escalated, every
high-idle reading with the failure count, and when it turned off.

To make the app forget the already-verified mode and rediscover it from
scratch:

```bash
defaults delete com.rootless.presence verifiedActivityMode
```

## Architecture

```
Sources/PresenceCore/     logic, no UI and no lifecycle dependency
  IdleReader              reads HIDIdleTime via IOKit
  ActivityDeclarer        IOPMAssertionDeclareUserActivity
  SyntheticInput          F15 key via CGEvent, on .cghidEventTap
  LockMonitor             screen lock and unlock
  Preferences             UserDefaults
  PresenceController      state machine and check loop

Sources/Presence/         app layer
  PresenceApp             MenuBarExtra, LSUIElement
  PresenceRunner          30s cadence, App Nap, lifecycle
  MenuView                the menu
  LunchSettingsView       the lunch break settings window
  LoginItem               SMAppService

Sources/idle-probe/       the measurement probe
```

Every system dependency comes in through a protocol, so the whole loop runs
across the 56 tests without touching IOKit and without waiting on real time.

## How this was verified

Green tests don't prove an app like this works — they prove the logic around
the mechanism, not the mechanism. The end-to-end verification was observing
`HIDIdleTime` from outside, every 15 seconds, with the app active and nobody
touching the machine:

```
09:09-09:11   16 → 31 → 46 → 6 → 21 → 36 → 51 → 66 → 81 → 96 → 111   (app not yet acting)
09:12:05      0.4                                                     (starts acting)
09:13-09:29   13 → 28 → 10 → 26 → 8 → 23 → 6 → 21 → 4 → 19 → 1 → 16  (sawtooth)
```

After stabilizing, the counter never exceeded **31.9s** — exactly the 30s
cycle plus the one-second check — with a mechanical pattern, not a human one.
Teams stayed green for over 40 minutes.

## Warning

Some companies have policies about tools that alter presence indicators.
Check your employer's rules before using this.

## License

MIT — see [LICENSE](LICENSE).
