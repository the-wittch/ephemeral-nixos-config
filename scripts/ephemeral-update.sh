#!/usr/bin/env bash

set -euo pipefail

flake=$(flake_dir)
installed=${EPHEMERAL_INSTALLED_DIR:-/persist/etc/nixos-install}
repo=$(release_repo)

usage() {
  cat <<'USAGE'
ephemeral-update [--now | --check | --previous | --as-installed | --list]

With no option: offer a newer release if there is one, then rebuild from
/persist/etc/nixos and switch to it. On a handheld it's used from the next
restart instead, so a running game or Game Mode isn't cut off.

  --now           on a handheld, switch to it straight away
  --check         build it without switching, to see whether a change works
  --previous      go back to the system before the last rebuild
  --as-installed  rebuild the system as it was installed; your files stay
  --list          the systems you can go back to, with their dates and releases
USAGE
}

mode=switch
# Switching live restarts services under the running session, and across nixpkgs versions some
# have failed to come back until a restart. A handheld is in Game Mode while that happens, so it
# takes the new system at the next restart.
at_boot=
[[ -e ${EPHEMERAL_ROOT:-}/etc/ephemeral/update-at-boot ]] && at_boot=1
case ${1:-} in
  -h | --help)
    usage
    exit 0
    ;;
  --now)
    at_boot=
    shift
    ;;
  --check) mode=check ;;
  --previous) mode=previous ;;
  --as-installed) mode=installed ;;
  --list) mode=list ;;
  -*) usage_error ;;
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
    FLAKE_DIR=$installed make_initrd_ssh_key
    echo "Rebuilding the system as it was installed. Your files and $flake stay as they are."
    nh os switch "path:$installed" --hostname nixos "$@"
    echo "To go back to your own config: ephemeral-update"
    exit 0
    ;;
esac

flake=$(require_flake)
refuse_secret_files "$flake"

if [[ $mode == check ]]; then
  echo "Building $flake without switching to it."
  nh os build "path:$flake" --hostname nixos "$@"
  echo "It builds. Run ephemeral-update to switch to it."
  exit 0
fi

if flake_needs_owner "$flake" &&
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

pinned=$(pinned_release "$flake")
latest=
# offline, or GitHub slow to answer: latest is empty, and the release already pinned is rebuilt
if [[ -n $pinned && -t 0 ]]; then
  latest=$(latest_release)
fi

if is_newer "$latest" "$pinned"; then
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

make_initrd_ssh_key
# a release can change what's kept on /persist, so there's a copy from just before it to go back to
if [[ -e ${EPHEMERAL_ROOT:-}/etc/snapper/configs/persist ]]; then
  sudo snapper -c persist create --cleanup-algorithm number \
    --description "before ephemeral update from $(cat /etc/ephemeral/release 2>/dev/null || echo "an unknown release")" ||
    echo "Couldn't take a snapshot of /persist first; updating anyway." >&2
fi
if [[ -n $at_boot ]]; then
  nh os boot "path:${flake}" --hostname nixos "$@"
  trap - ERR
  echo "Built. It's used from the next restart; until then this system stays as it is."
  echo "To switch to it now instead: ephemeral-update --now"
  echo "If something's wrong after the restart: pick the previous entry in the boot menu."
else
  nh os switch "path:${flake}" --hostname nixos "$@"
  trap - ERR
  echo "If something's wrong now: ephemeral-update --previous, or pick the previous entry in the boot menu."
fi

asked=${XDG_STATE_HOME:-$HOME/.local/state}/ephemeral/apps-asked
if [[ -t 0 && ! -e $flake/apps.json && ! -e $asked ]] && command -v ephemeral-apps >/dev/null; then
  mkdir -p "$(dirname "$asked")"
  touch "$asked"
  if ask "Pick apps now? You can run ephemeral-apps any time."; then
    exec ephemeral-apps
  fi
fi
