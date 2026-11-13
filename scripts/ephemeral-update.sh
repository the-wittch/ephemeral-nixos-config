#!/usr/bin/env bash

set -euo pipefail

flake=${FLAKE_DIR:-/persist/etc/nixos}
installed=${EPHEMERAL_INSTALLED_DIR:-/persist/etc/nixos-install}
repo=the-wittch/ephemeral-nixos-config

usage() {
  cat <<'USAGE'
ephemeral-update [--check | --previous | --as-installed | --list]

With no option: offer a newer release if there is one, then rebuild from
/persist/etc/nixos and switch to it.

  --check         build it without switching, to see whether a change works
  --previous      go back to the system before the last rebuild
  --as-installed  rebuild the system as it was installed; your files stay
  --list          the systems you can go back to, with their dates and releases
USAGE
}

mode=switch
case ${1:-} in
  -h | --help)
    usage
    exit 0
    ;;
  --check) mode=check ;;
  --previous) mode=previous ;;
  --as-installed) mode=installed ;;
  --list) mode=list ;;
  -*)
    usage >&2
    exit 2
    ;;
esac
[[ $mode == switch ]] || shift

case $mode in
  list)
    nh os info
    echo
    echo "Config release of each:"
    for link in /nix/var/nix/profiles/system-*-link; do
      [[ -e $link ]] || continue
      n=${link##*/system-}
      printf '  %-4s %s\n' "${n%-link}" "$(cat "$link/etc/ephemeral/release" 2>/dev/null || echo "before v4.1.0")"
    done | sort -n
    exit 0
    ;;
  previous)
    nh os rollback
    echo "Back on the system from before the last rebuild, config $(cat /etc/ephemeral/release 2>/dev/null || echo "from before v4.1.0")."
    echo "The next ephemeral-update builds /persist/etc/nixos again; fix what broke there first."
    exit 0
    ;;
  installed)
    [[ -f $installed/flake.nix ]] || die "there's no copy of the installed system in $installed; it's kept by installs from v3.0.0 on"
    echo "Rebuilding the system as it was installed. Your files and $flake stay as they are."
    nh os switch "path:$installed" --hostname nixos "$@"
    echo "To go back to your own config: ephemeral-update"
    exit 0
    ;;
esac

if [[ ! -f $flake/flake.nix ]]; then
  [[ -d $flake && ! -r $flake ]] && die "can't read $flake; fix it with: sudo chmod 755 $flake"
  die "no flake at $flake"
fi
refuse_secret_files "$flake"

if [[ $mode == check ]]; then
  echo "Building $flake without switching to it."
  nh os build "path:$flake" --hostname nixos "$@"
  echo "It builds. Run ephemeral-update to switch to it."
  exit 0
fi

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

# the CHANGELOG.md entries newer than $1, up to $2, for showing before moving
changes_between() {
  curl -fsS --max-time 5 "https://raw.githubusercontent.com/$repo/$2/CHANGELOG.md" 2>/dev/null |
    awk -v stop="## ${1#v}" '/^## [0-9]/ { if ($0 == stop) exit; on = 1 } on' || true
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
  echo "$latest is out; this machine is on $pinned. What changed since:"
  echo
  changes=$(changes_between "$pinned" "$latest")
  if [[ -n $changes ]]; then
    printf '%s\n' "$changes" | sed 's/^/  /'
  else
    echo "  https://github.com/$repo/blob/main/CHANGELOG.md"
  fi
  echo
  question="Move to $latest?"
  if [[ ${latest%%.*} != "${pinned%%.*}" ]]; then
    echo "It's a new major version. Its Breaking section above says what you may have to change first."
    question="Move to $latest, a new major version?"
  fi
  if ask "$question"; then
    as_owner sed -i "s#\"github:$repo/$pinned\"#\"github:$repo/$latest\"#" "$flake/flake.nix"
    as_owner nix flake update ephemeral --flake "path:$flake"
    trap 'echo "The rebuild failed on $latest. To go back, set the tag in $flake/flake.nix to $pinned, then run: nix flake update ephemeral --flake path:$flake && ephemeral-update" >&2' ERR
  fi
fi

nh os switch "path:${flake}" --hostname nixos "$@"
trap - ERR
echo "If something's wrong now: ephemeral-update --previous, or pick the previous entry in the boot menu."

asked=${XDG_STATE_HOME:-$HOME/.local/state}/ephemeral/apps-asked
if [[ -t 0 && ! -e $flake/apps.json && ! -e $asked ]] && command -v ephemeral-apps >/dev/null; then
  mkdir -p "$(dirname "$asked")"
  touch "$asked"
  read -r -p "Pick extra apps now? You can run ephemeral-apps any time. [y/N] " answer
  if [[ ${answer:-n} =~ ^[Yy] ]]; then
    exec ephemeral-apps
  fi
fi
