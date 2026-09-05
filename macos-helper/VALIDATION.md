# Local validation — September 5, 2026

- Direct Swift compiler build succeeded with the installed command-line tools.
- Six standalone test groups passed: both palettes, new-work/completion race,
  completion deduplication, malformed/stale/future events, lease expiry/order,
  bounded reconnect backoff.
- Installed bundle signature verified; NSBluetoothAlwaysUsageDescription is present.
- User approved the native app's macOS Bluetooth dialog.
- Native helper connected to MOONSIDE-O101 and retained the discovered UUID.
- All six colors were sent successfully; user visually confirmed Claude
  blue/purple/green and Codex cyan/amber/white, including return to off.
- Actual Codex tool-use/approval events were observed by the running helper.
- Legacy Python daemon was stopped; existing hook was backed up at
  `~/Library/Application Support/Moonside Agent Lamp/backups/hooks-20260905-140757/`.
- Installed shared hook now writes only the native app mailbox. Claude and Codex
  hook configurations and Pixoo were not edited.
- With the helper stopped, invoking the installed hook launched no helper or Python
  daemon. Reopening via LaunchServices reconnected without another permission dialog.
- Login registration reports enabled through SMAppService.mainApp.
- Remaining Python crash reports dated September 5 were from 07:00–07:21,
  before native installation at approximately 14:07 local time.

## Pre-publication update (1.0.1)

- Rebuilt app with explicit macOS 13.0 compiler targets; `vtool -show-build`
  confirms the executable's minimum OS is 13.0. Older-macOS execution remains untested.
- All six test groups, both hook JSON examples, and all shell syntax checks pass.
- Fresh hook installation and repeat-install backup were exercised in an isolated
  temporary directory without any legacy scripts installed there.
- The installed app was updated with a backup of version 1.0.0. Its menu uses
  Claude/Codex display names, and it reconnected to the Halo with authorization
  granted and login startup enabled after the rebuild. This single successful
  update does not guarantee permission retention across all future updates.
- Added fresh Claude/Codex configuration examples, upstream attribution, and
  lessons learned. Generated app bundles and compiler output remain ignored by Git.

At this stage, logout/login, sleep/wake, physical unplug/replug, Bluetooth off/on,
older-macOS execution, and Intel hardware had not been exercised. See the later
hardware retest below for updated results.

## Automated recovery coverage added September 5, 2026

- Extracted connection policy and write serialization into `LampCore/Recovery.swift`
  and wired the actual macOS app to those components. This is a production refactor,
  not a separate simulated copy of the app's recovery rules.
- Six existing test groups and 15 new recovery tests pass. The recovery tests use
  supplied timestamps and injected outcomes, with no hardware, real timers, or sleeps.
- Covered discovery/connection/service deadlines, disconnect/retry and backoff reset,
  unavailable/denied/re-enabled Bluetooth, revocation during a write, interrupted
  writes and timeouts, latest-state precedence, stale write acknowledgements,
  sleep/retry cancellation, pause persistence, post-wake display expiry, and quit.
- Hook-example checks, shell syntax checks, macOS app compilation, signature
  verification, and executable minimum-OS verification (13.0) pass.
- The updated source no longer schedules delayed write callbacks to drain commands;
  its queue owns pacing and invalidates old write IDs on disconnect. Discovery
  callbacks are gated by the active connection phase and sleep/permission state.
- At the time these tests were added, the refactored build had not replaced the
  installed app. The following hardware retest subsequently exercised that build.

## Hardware retest of recovery refactor (6647ff5)

The user reported completing the update/build/install, executable comparison,
six-color menu test, completion-to-off check, and physical unplug/replug test on
September 5, 2026. They had not yet run separate short tasks in both agents.

- Independently compared the installed executable with the repository build:
  they match. The checkout is at recovery-refactor commit `6647ff5`.
- Helper log shows restart at 18:37:17 UTC and connection at 18:37:20 UTC.
- All six color command sequences and completion-to-off transitions appear in
  the log between 18:37:50 and 18:38:19 UTC, corroborating the user's visual test.
- Physical disconnect was recorded at 18:38:43 UTC. The helper retried with
  increasing delays and reconnected automatically at 18:39:12 UTC (29 seconds
  after detection; this includes time the lamp was unplugged).
- Post-reconnect amber/white tests returned to off. The helper reported Bluetooth
  authorization granted and login startup enabled.
- The user's follow-up Codex prompt served as the live Codex task check:
  `codex-working` / cyan was logged at 18:39:43 UTC, followed by the approval/input
  event. Completion from that still-running task was not yet available at the time
  this record was written; completion itself passed the menu test above.

Still pending: a separate live Claude task on the refactored build, actual OS
sleep/wake and logout/login, Bluetooth off/on via system settings, macOS 13
execution, and Intel hardware. Automated simulations cover the relevant recovery
policy but are not claimed as substitutes for these physical/platform checks.
