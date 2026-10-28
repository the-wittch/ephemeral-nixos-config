#!/usr/bin/env bash

set -euo pipefail

flake=/persist/etc/nixos
if [[ ! -f $flake/flake.nix ]]; then
  echo "no flake at $flake" >&2
  exit 1
fi

nh os switch "path:${flake}" --hostname nixos "$@"

asked=${XDG_STATE_HOME:-$HOME/.local/state}/ephemeral/apps-asked
if [[ -t 0 && ! -e $flake/apps.json && ! -e $asked ]] && command -v ephemeral-apps >/dev/null; then
  mkdir -p "$(dirname "$asked")"
  touch "$asked"
  read -r -p "Pick extra apps now? You can run ephemeral-apps any time. [y/N] " answer
  if [[ ${answer:-n} =~ ^[Yy] ]]; then
    exec ephemeral-apps
  fi
fi
