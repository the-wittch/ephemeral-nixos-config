#!/usr/bin/env bash
# INSTALLER_DIR=<checkout> or INSTALLER_REF=<tag> compares another copy

set -euo pipefail

SHARED=(
  assets/wallpaper.svg
  modules/flake/parts.nix
  modules/host-builder.nix
  modules/hosts/nixos.nix
  modules/settings/_load.nix
  modules/settings/_read-data.nix
  modules/settings/options.nix
  modules/pc.nix
  modules/system.nix
  modules/nix.nix
  modules/networking.nix
  modules/ssh.nix
  modules/memory.nix
  modules/boot.nix
  modules/disko.nix
  modules/persist.nix
  modules/users.nix
  modules/unfree.nix
  modules/hardening.nix
  modules/audio.nix
  modules/hardware.nix
  modules/printing.nix
  modules/fonts.nix
  modules/podman.nix
  modules/flathub.nix
  modules/wallpaper.nix
  modules/dotfiles/zsh.nix
  modules/dotfiles/chezmoi.nix
)
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
