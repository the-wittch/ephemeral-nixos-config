#!/usr/bin/env bash
# shared modules must match the installer's copy
#
#   check-shared                                     # compare with installer main
#   INSTALLER_DIR=~/Projects/ephemeral-nixos check-shared
#   INSTALLER_REF=v1.2.0 check-shared

set -euo pipefail

SHARED=(boot.nix persist.nix users.nix disko.nix unfree.nix hardening.nix flathub.nix wallpaper.nix assets/wallpaper.svg lib/read-data.nix)
INSTALLER_URL=${INSTALLER_URL:-https://github.com/the-wittch/ephemeral-nixos.git}
INSTALLER_REF=${INSTALLER_REF:-main}

root=$(git rev-parse --show-toplevel)

if [[ -n ${INSTALLER_DIR:-} ]]; then
  other=$INSTALLER_DIR
  where=$INSTALLER_DIR
else
  other=$(mktemp -d)
  trap 'rm -rf "$other"' EXIT
  git clone -q --depth 1 --branch "$INSTALLER_REF" "$INSTALLER_URL" "$other"
  where="$INSTALLER_URL@$INSTALLER_REF"
fi

fail=0
for f in "${SHARED[@]}"; do
  if [[ ! -f $other/$f ]]; then
    echo "missing in installer: $f" >&2
    fail=1
  elif ! diff -u --label "installer/$f" --label "config/$f" "$other/$f" "$root/$f"; then
    fail=1
  fi
done

if [[ $fail -ne 0 ]]; then
  echo >&2
  echo "Shared modules differ from $where." >&2
  echo "Make the same change in both repos." >&2
  exit 1
fi

echo "Shared modules match $where."
