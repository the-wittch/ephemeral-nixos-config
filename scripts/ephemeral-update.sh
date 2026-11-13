#!/usr/bin/env bash

set -euo pipefail

flake=/persist/etc/nixos
repo=the-wittch/ephemeral-nixos-config

if [[ ! -f $flake/flake.nix ]]; then
  [[ -d $flake && ! -r $flake ]] && die "can't read $flake; fix it with: sudo chmod 755 $flake"
  die "no flake at $flake"
fi
refuse_secret_files "$flake"

ask() {
  local answer
  [[ -t 0 ]] || return 1
  read -r -p "$1 [y/N] " answer
  [[ ${answer:-n} =~ ^[Yy] ]]
}

# the installer leaves the flake to root, which keeps you from updating its lock or editing it
if [[ ! -w $flake/flake.lock ]] &&
  ask "$flake belongs to root. Make it yours, so it can be updated and edited?"; then
  sudo chown -R "$USER": "$flake"
fi

as_owner() {
  if [[ -w $flake/flake.nix && -w $flake/flake.lock ]]; then
    "$@"
  else
    sudo env PATH="$PATH" "$@"
  fi
}

pinned=$(sed -nE "s#.*\"github:$repo/(v[0-9]+\.[0-9]+\.[0-9]+)\".*#\1#p" "$flake/flake.nix" | head -n 1)
latest=
if [[ -n $pinned && -t 0 ]]; then
  # offline, or GitHub slow to answer: carry on with the release already pinned
  latest=$(curl -fsS --max-time 5 "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null |
    jq -r '.tag_name // empty' 2>/dev/null) || latest=
  [[ $latest =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || latest=
fi

if [[ -n $latest && $latest != "$pinned" && $(printf '%s\n' "$pinned" "$latest" | sort -V | tail -n 1) == "$latest" ]]; then
  echo "$latest is out; this machine is on $pinned."
  echo "What changed: https://github.com/$repo/blob/main/CHANGELOG.md"
  if [[ ${latest%%.*} != "${pinned%%.*}" ]]; then
    echo "It's a new major version. Read its Breaking section first; it says what to change."
  fi
  if ask "Move to $latest?"; then
    as_owner sed -i "s#\"github:$repo/$pinned\"#\"github:$repo/$latest\"#" "$flake/flake.nix"
    as_owner nix flake update ephemeral --flake "path:$flake"
    trap 'echo "The rebuild failed on $latest. To go back, set the tag in $flake/flake.nix to $pinned, then run: nix flake update ephemeral --flake path:$flake && ephemeral-update" >&2' ERR
  fi
fi

nh os switch "path:${flake}" --hostname nixos "$@"
trap - ERR

asked=${XDG_STATE_HOME:-$HOME/.local/state}/ephemeral/apps-asked
if [[ -t 0 && ! -e $flake/apps.json && ! -e $asked ]] && command -v ephemeral-apps >/dev/null; then
  mkdir -p "$(dirname "$asked")"
  touch "$asked"
  read -r -p "Pick extra apps now? You can run ephemeral-apps any time. [y/N] " answer
  if [[ ${answer:-n} =~ ^[Yy] ]]; then
    exec ephemeral-apps
  fi
fi
