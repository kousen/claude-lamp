#!/bin/bash
# Install the native state-only hook for a fresh setup; no legacy scripts needed.
# An optional destination directory supports isolated installation checks.
set -euo pipefail
helper_root=$(cd "$(dirname "$0")/.." && pwd)
hook_dir="${1:-$HOME/Library/Application Support/Moonside Agent Lamp}"
umask 077
mkdir -p "$hook_dir"
if [ -e "$hook_dir/moonside_hook.sh" ]; then
    backup_dir=$(mktemp -d "$hook_dir/hook-backup.XXXXXX")
    cp -p "$hook_dir/moonside_hook.sh" "$backup_dir/"
fi
install -m 755 "$helper_root/scripts/moonside_hook.sh" "$hook_dir/moonside_hook.sh"
printf 'Installed %s\nMerge the example hooks into your agent configuration as described in README.md.\n' "$hook_dir/moonside_hook.sh"
