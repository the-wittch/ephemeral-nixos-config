#!/usr/bin/env bash

set -euo pipefail

case ${1:-} in
  -h | --help)
    echo "ephemeral-report: system details for a bug report. Leaves out user, host and vault names; read it before posting."
    exit 0
    ;;
esac

FLAKE_DIR=${FLAKE_DIR:-/persist/etc/nixos}
settings=$FLAKE_DIR/settings.json

echo "## ephemeral-report"
echo
echo "- NixOS: $(nixos-version 2>/dev/null || echo unknown)"
echo "- kernel: $(uname -r)"
if [[ -f $FLAKE_DIR/flake.lock ]]; then
  jq -r '
    .nodes as $n
    | ($n.root.inputs.ephemeral // empty) as $e
    | $n[$e].original.ref // $n[$e].locked.rev // "unknown"
    | "- template: \(.)"
  ' "$FLAKE_DIR/flake.lock"
fi
if [[ -f $settings ]]; then
  jq -r '
    to_entries
    | map(select(.key | IN("username", "hostname", "passSettingsItem", "passSettingsVault", "passSshVault") | not))
    | map("  - \(.key): \(.value)")
    | "- settings:\n" + join("\n")
  ' "$settings"
fi
if [[ -f $FLAKE_DIR/apps.json ]]; then
  echo "- apps: $(jq -r 'join(", ")' "$FLAKE_DIR/apps.json")"
fi
echo "- session: ${XDG_CURRENT_DESKTOP:-none} on ${XDG_SESSION_TYPE:-unknown}"
echo "- GPU: $(lspci 2>/dev/null | grep -iE 'vga|3d|display' | cut -d: -f3- | paste -sd ';' | sed 's/^ *//' || echo unknown)"
echo
echo "### failed units"
echo
echo '```'
systemctl --failed --no-legend --plain 2>/dev/null || true
systemctl --user --failed --no-legend --plain 2>/dev/null || true
echo '```'
echo
echo "### errors this boot (last 30)"
echo
echo '```'
journalctl -b -p err --no-pager -o short-monotonic 2>/dev/null | tail -n 30 | sed "s/ $(hostname) / /" || true
echo '```'
