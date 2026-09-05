#!/bin/bash
# Installs the app only. Migrate hooks separately after the hardware check.
set -euo pipefail
helper_root=$(cd "$(dirname "$0")/.." && pwd)
source_app="$helper_root/dist/Moonside Agent Lamp.app"
target_app="$HOME/Applications/Moonside Agent Lamp.app"
support="$HOME/Library/Application Support/Moonside Agent Lamp"
codesign --verify --strict "$source_app"
if pgrep -x MoonsideAgentLamp >/dev/null; then
    echo 'Quit Moonside Agent Lamp from its menu before installing an update.' >&2
    exit 1
fi
umask 077
mkdir -p "$HOME/Applications" "$support/backups"
if [ -e "$target_app" ]; then
    mv "$target_app" "$support/backups/app-$(date +%Y%m%d-%H%M%S).previous"
fi
ditto "$source_app" "$target_app"
codesign --verify --strict "$target_app"
open "$target_app" --args --enable-login
printf 'Installed %s\nApprove Bluetooth access when macOS asks.\n' "$target_app"
