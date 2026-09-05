# Moonside Agent Lamp for macOS

A small Swift/AppKit menu-bar app owns the Halo's CoreBluetooth connection. Claude
and Codex hooks publish state to a private mailbox; they never launch Python or
request Bluetooth access. No Python/Bleak dependency is used by the new runtime.

## Build and install

Requires macOS 13+ and Swift 5.9 or newer command-line tools. Full Xcode is
unnecessary. The build script explicitly targets macOS 13.0 for the build Mac's
architecture (Apple Silicon or Intel); it does not produce a universal binary.
Hardware testing so far is on Apple Silicon with macOS 26.6.2, not macOS 13.

```sh
git clone https://github.com/kousen/claude-lamp.git
cd claude-lamp/macos-helper
bash scripts/test.sh
bash scripts/build.sh
bash scripts/install.sh
```

The build script uses `swiftc` directly because the local SwiftPM installation
has mismatched PackageDescription components. A Package.swift is also provided
for compatible toolchains (`swift build`, `swift run LampTests`). Tests use a
standalone assertion runner so Apple's XCTest framework is not required.
If you already cloned this repository, start from its `macos-helper` directory
and omit the clone command. The compiler target, Package.swift platform, and
app Info.plist all declare macOS 13 as the minimum.

Installation places the bundle in `~/Applications/Moonside Agent Lamp.app` and
registers the main app as a login item using `SMAppService.mainApp`. The installer
opens the bundle through LaunchServices. Approve Bluetooth for **Moonside Agent
Lamp**, then check that its lightbulb menu says **Connected to MOONSIDE…**.
If macOS requires login-item approval, use System Settings → General → Login Items.

The default signature is ad hoc, for this Mac. To use an existing certificate:

```sh
MOONSIDE_SIGN_IDENTITY='Your signing identity' bash scripts/build.sh
```

A stable bundle ID alone does not guarantee that privacy grants survive rebuilding
an ad-hoc-signed app. Recheck authorization after updates. This is a local app,
not a notarized public distribution. No system Python bundles are modified.

## Fresh hook setup (no Python required)

After installing and testing the app, install its state-only shell hook:

```sh
bash scripts/install-hook.sh
```

The hook is installed in `~/Library/Application Support/Moonside Agent Lamp/`.
It does not require Claude's legacy scripts or Bleak. Enable whichever agents
you use by merging the corresponding example into their configuration:

| Agent | Example | Destination |
| --- | --- | --- |
| Claude Code (including desktop-launched sessions) | [claude-settings.json](examples/claude-settings.json) | `~/.claude/settings.json` |
| Codex | [codex-hooks.json](examples/codex-hooks.json) | `~/.codex/hooks.json` |

If the destination does not exist, create its parent directory and copy the
example to that destination. If it exists, back it up and append the example's
handlers under the matching event keys inside `hooks`; preserve other keys and
existing handlers. Do not replace an existing configuration file wholesale.
Install the lamp handlers only once to avoid duplicate notifications. Commands
quote `$HOME` so they work with spaces in the path.

Start a new agent session after editing. In Codex, use `/hooks` to review and trust
the new commands; a saved JSON file by itself does not establish hook trust.
Do not disable hook trust globally. See the official
[Codex hooks reference](https://learn.chatgpt.com/docs/hooks) and
[Claude Code hooks reference](https://code.claude.com/docs/en/hooks).
The examples show working, permission-request, completion, and session-end events;
Claude additionally has question-tool and notification matchers. They are not
intended to detect every possible conversational request for user input.

For a quick manual check (with the helper open and connected):

```sh
bash "$HOME/Library/Application Support/Moonside Agent Lamp/moonside_hook.sh" codex-done
```

This should produce the white completion flash, then turn off.

## Migrate an existing Python-based setup

First release the lamp from any old Python daemon (verify its executable before
stopping it). Connect and test this app before migrating:

```sh
bash scripts/migrate-hooks.sh
```

This backs up both installed legacy scripts under the app's Application Support
directory and replaces only `~/.claude/moonside_hooks/moonside_hook.sh`. Existing
Claude/Codex hook configurations continue to call the same path. Pixoo is unaffected.
The legacy daemon remains on disk for reference but is no longer launched by hooks.
Repository `claude_hooks/` retains the original upstream Python implementation;
the native palette was reconciled against the enhanced installed version.
This migration path assumes both old scripts exist at those paths. It does not
create missing agent hook configuration. For a new installation, use the fresh
setup above instead; do not install Python just to satisfy migration prerequisites.

| State | Claude | Codex |
| --- | --- | --- |
| Working | Dim blue (0,60,255) | Dim cyan (0,220,255) |
| Approval/input | Purple (200,0,255) | Amber (255,120,0) |
| Completed | Green (0,255,60) | White (255,255,255) |
| Idle/session end | Off | Off |

Completion displays for three seconds. New activity supersedes it. A 30-minute
inactivity lease prevents forgotten working/input colors from staying on indefinitely.
Session end and inactivity turn the light off, but keep the helper available.
Repeated events with fresh IDs refresh the lease; the helper never overwrites the
hook mailbox. Events older than app launch are ignored. Completion events older
than ten seconds are rejected. A file mailbox deliberately keeps only the latest
event: this is a status indicator, not a durable event queue.

## Controls and recovery

- **Reconnect** restarts discovery with a bounded exponential retry (up to 60s).
- **Pause & Disconnect** releases Bluetooth for the Moonside phone app. **Resume**
  reconnects. The helper remembers the first successfully connected lamp UUID.
- **Test Lamp** can show every Claude/Codex state without invoking an agent.
  Labels identify the source: **Claude: Working**, **Claude: Needs Input**,
  **Claude: Done**, and the corresponding Codex entries, plus **Turn Off**.
- **Start at Login** controls login registration; **Quit** exits the app.
- **Bluetooth Settings** opens permission settings; **Show Diagnostics** reveals logs.

Bluetooth-off, missing lamp, permission denial, sleep/wake, and write timeouts do
not terminate the app. All BLE writes are serialized and acknowledged at the GATT
layer. This does not prove the lamp displayed the requested color: visual validation
is still required. Retrying discovery after permission changes may require Reconnect
or reopening the app. Hooks silently return success if their mailbox cannot be written.

Runtime files are under `~/Library/Application Support/Moonside Agent Lamp/`:
`event` (atomic version/timestamp/UUID/state), `status.json` (diagnostics),
`helper.log` (rotated at 1 MB), and `helper.lock` (single-instance flock).
No prompts, code, or transcripts are stored. Backups live in `backups/`.

## Acceptance checks

1. Open the installed .app through Finder; approve Bluetooth for its own identity.
2. Connect the Halo and visually verify all six colors and the three-second flash.
3. Quit and reopen; confirm no fresh permission prompt or Python crash report.
4. Verify login registration and, when convenient, log out/in to test actual login startup.
5. Unplug/replug the Halo and toggle Bluetooth; confirm automatic recovery.
6. Start new Claude Desktop and Codex tasks; verify their hook-driven feedback.
7. Quit the helper and run a hook: no Python, BLE process, or crash dialog should start.

For a demo, power on the Halo, confirm **Connected** in the menu, use **Test Lamp**,
and leave the phone app disconnected. If unavailable, agents continue normally.

## Rollback and uninstall

To remove automatic startup, turn off **Start at Login**, then **Quit**. Move
`~/Applications/Moonside Agent Lamp.app` to Trash. This leaves the state-only hooks
harmlessly writing their mailbox. Keep them this way if reverting due to Bluetooth
problems; automatically restoring the Python launcher would restore the TCC risk.

If deliberately returning to the old setup, copy `moonside_hook.sh` from the desired
timestamped backup to `~/.claude/moonside_hooks/moonside_hook.sh`. The original
Python daemon was never deleted or modified by migration. App updates are backed
up as `app-*.previous`; quit the current version before restoring a backup bundle.

## Attribution and lessons

This fork builds on Bobby Bobak's
[bobek-balinek/claude-lamp](https://github.com/bobek-balinek/claude-lamp), which
provided the original Claude hook/Bleak daemon and Moonside command examples.
The original MIT license and copyright notice are retained in [LICENSE](../LICENSE).
The native helper adds an independent macOS Bluetooth identity and distinct
Claude/Codex feedback. See [Lessons learned](../LESSONS_LEARNED.md) and
[Local validation](VALIDATION.md) for the evidence and remaining checks.
