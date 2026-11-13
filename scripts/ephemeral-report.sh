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
user=$(id -un)
host=$(hostname)

# everything goes through this, so no line has the user or host name in it
scrub() { sed -e "s/\\<$host\\>/<host>/g" -e "s/\\<$user\\>/<user>/g"; }

report() {
  echo "## ephemeral-report"
  echo
  echo "User, host and vault names are left out. Read it before posting anyway."
  echo
  echo "- NixOS: $(nixos-version 2>/dev/null || echo unknown)"
  echo "- kernel: $(uname -r)"
  echo "- config release this system was built from: $(cat /etc/ephemeral/release 2>/dev/null || echo "before v4.1.0")"
  if [[ -f $FLAKE_DIR/flake.lock ]]; then
    jq -r '
      .nodes as $n
      | ($n.root.inputs.ephemeral // empty) as $e
      | $n[$e].original.ref // $n[$e].locked.rev // "unknown"
      | "- pinned in the flake: \(.)"
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

  if command -v ephemeral-doctor >/dev/null; then
    echo
    echo "### ephemeral-doctor"
    echo
    echo '```'
    ephemeral-doctor 2>&1 || true
    echo '```'
  fi

  echo
  echo "### systems to go back to"
  echo
  echo '```'
  for link in /nix/var/nix/profiles/system-*-link; do
    [[ -e $link ]] || continue
    n=${link##*/system-}
    printf '%-4s %s  %s\n' "${n%-link}" "$(date -r "$link" +%F)" "$(cat "$link/etc/ephemeral/release" 2>/dev/null || echo "before v4.1.0")"
  done | sort -n | tail -n 6
  echo '```'

  local failed unit
  failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{ print $1 }')
  echo
  echo "### failed services"
  echo
  if [[ -z $failed ]]; then
    echo "none"
  fi
  for unit in $failed; do
    echo "#### $unit"
    echo
    echo '```'
    journalctl -b -u "$unit" -n 15 --no-pager -o short-monotonic 2>/dev/null || echo "(no log readable as this user)"
    echo '```'
  done
  echo
  echo "### errors this boot (last 30)"
  echo
  echo '```'
  journalctl -b -p err --no-pager -o short-monotonic 2>/dev/null | tail -n 30 || true
  echo '```'
}

report | scrub
