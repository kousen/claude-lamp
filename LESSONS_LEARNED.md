# Lessons learned: a Halo lamp shared by Claude and Codex

Recorded September 5, 2026. This fork extends Bobby Bobak's
[original Claude Lamp project](https://github.com/bobek-balinek/claude-lamp).
Its MIT license and attribution remain intact.

## Test the real launch path

A Bluetooth script working from Terminal does not prove it will work when launched
by a desktop agent. The Python crash reports showed a TCC privacy termination,
the missing `NSBluetoothAlwaysUsageDescription` key, and Claude as the responsible
process. That evidence pointed to macOS application identity and authorization;
it was not proof of a defect in Bleak's Bluetooth implementation.

The replacement must be tested as an installed `.app`, launched through macOS,
with permission granted to the helper itself. A successful foreground compiler
or shell test alone is insufficient. Background processes started by an agent's
test runner may also be cleaned up at the end of its command; distinguish runner
behavior from normal application lifetime.

## Give Bluetooth one owner

The native Swift helper owns one CoreBluetooth connection. Both agents send status
through a small local mailbox. This removes Python startup, BLE discovery, and
permission prompts from routine hook execution. Missing hardware should cause
bounded retries in the helper, while agent work continues. Pause/disconnect provides
a way to release the lamp for its phone app.

Appending `|| true` can prevent a hook failure from interrupting an agent, but it
cannot prevent macOS from killing a child for a privacy violation or displaying
its crash report. The fix needs to address that child's launch and permission model.

## Keep event handling small and explicit

Hooks write a version, timestamp, unique event ID, and state using atomic replacement
in a user-owned directory. The helper owns display timers and never writes back to
the mailbox. This prevents an old completion timer from overwriting new activity.
Stale and prelaunch events are ignored. Repeated working events refresh an inactivity
lease without resending every color command.

This is intentionally a latest-state mailbox, not an event queue. It suits one user
switching between agents. Simultaneous sessions still compete for the same light;
per-session arbitration would be a separate feature.

## Packaging is part of the product

The bundle, compiler deployment target, and advertised minimum OS must agree.
The initial direct Swift build accidentally inherited macOS 26.0 while the plist
claimed 13.0. An explicit compiler target fixes that discrepancy; running on an older
OS still needs separate validation. The current script builds for the host's CPU,
not both architectures.

A stable bundle ID is not a guarantee that ad-hoc-signed updates retain permission.
Use a stable signing identity when available, and test an update before promising
permanent authorization. Avoid modifying a shared Python installation's plist.

## Make it understandable and reproducible

Use UI labels such as “Claude: Working” rather than exposing internal wire values.
Distinct agent palettes should remain consistent across hooks, documentation, and
tests. Source control must contain the installed behavior: the original local
daemon had color and reliability improvements absent from its repository copy.

A public fork needs a fresh-install route as well as migration instructions.
Someone should not have to install the old runtime merely to replace it. Preserve
existing agent hooks while adding lamp handlers, and keep rollback backups local.

Record what was actually checked. The initial native build passed state-machine
tests, a six-color hardware test confirmed by the user, reopening/reconnection, and
the check that hooks cannot launch Python when the helper is closed. Login startup,
sleep/wake, physical disconnect recovery, and older-macOS execution remain separate
checks; registration or test coverage alone does not demonstrate them.

Keep optional analysis tools opt-in. Removing an integration may leave instructions
and hooks behind; check those separately. Do not add automatic Sonar scans to this
project's setup or tests.
