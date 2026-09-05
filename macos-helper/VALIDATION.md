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

Not yet exercised: actual logout/login, system sleep/wake, physical unplug/replug,
Bluetooth off/on, older-macOS execution, or Intel hardware.
The state/retry logic covers these cases, but hardware behavior is not claimed tested.

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
- This refactored build has **not** replaced the installed app or been physically
  retested. Earlier hardware results above apply to the previously installed build.
  Actual logout/login, OS sleep/wake, hardware disconnect/reconnect, and platform
  compatibility still require live verification; simulated tests do not replace them.
