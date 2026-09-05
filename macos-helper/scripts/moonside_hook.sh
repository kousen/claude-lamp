#!/bin/bash
# State-only bridge for both agents. Never launches Python or touches Bluetooth.
# Accepted arguments preserve the existing Claude and Codex hook definitions.
(
    set -eu
    umask 077
    state="${1:-idle}"
    case "$state" in
        idle|off|working|input|done|codex-working|codex-input|codex-done) ;;
        *) exit 0 ;;
    esac
    lamp_dir="$HOME/Library/Application Support/Moonside Agent Lamp"
    [ ! -L "$lamp_dir" ] || exit 0
    mkdir -p "$lamp_dir"
    [ -O "$lamp_dir" ] || exit 0
    chmod 700 "$lamp_dir"
    event_tmp=$(mktemp "$lamp_dir/.event.XXXXXX")
    trap 'rm -f "$event_tmp"' EXIT
    printf '1\t%s\t%s\t%s\n' "$(date +%s)" "$(uuidgen)" "$state" > "$event_tmp"
    mv -f "$event_tmp" "$lamp_dir/event"
) >/dev/null 2>&1 || true
exit 0
