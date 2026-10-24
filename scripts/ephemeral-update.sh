#!/usr/bin/env bash
# Rebuild the installed machine. Extra args are passed to nixos-rebuild.

set -euo pipefail

flake=/persist/etc/nixos
if [[ ! -f $flake/flake.nix ]]; then
  echo "no flake at $flake" >&2
  exit 1
fi

exec sudo nixos-rebuild switch --flake "path:${flake}#nixos" "$@"
