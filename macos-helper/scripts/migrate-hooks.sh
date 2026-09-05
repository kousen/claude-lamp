#!/bin/bash
# Both agents already call this installed shell path; preserve their hook configs.
set -euo pipefail
helper_root=$(cd "$(dirname "$0")/.." && pwd)
support="$HOME/Library/Application Support/Moonside Agent Lamp"
target="$HOME/.claude/moonside_hooks/moonside_hook.sh"
test -f "$support/status.json"
helper_pid=$(/usr/bin/plutil -extract pid raw "$support/status.json")
case "$helper_pid" in ''|*[!0-9]*) echo 'Invalid helper PID' >&2; exit 1;; esac
helper_command=$(ps -p "$helper_pid" -o command=)
case "$helper_command" in
    "$HOME/Applications/Moonside Agent Lamp.app/Contents/MacOS/MoonsideAgentLamp"*) ;;
    *) echo 'The installed native helper is not running' >&2; exit 1;;
esac
if ! /usr/bin/plutil -extract connection raw "$support/status.json" | /usr/bin/grep -q '^Connected to '; then
    echo 'Connect the native helper to the lamp before migrating hooks.' >&2
    exit 1
fi
umask 077
backup="$support/backups/hooks-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$backup"
cp -p "$target" "$backup/moonside_hook.sh"
cp -p "$HOME/.claude/moonside_hooks/moonside_daemon.py" "$backup/moonside_daemon.py"
install -m 755 "$helper_root/scripts/moonside_hook.sh" "$target"
printf 'Installed state-only hook. Previous scripts: %s\n' "$backup"
