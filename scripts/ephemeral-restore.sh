#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
ephemeral-restore <path>
Bring back a file or folder in your home folder, or anywhere on /persist, as it was in one of
the hourly snapshots. You pick the snapshot. What's there now is moved aside first, to
<path>.before-restore-<time>, so the restore can be undone.
USAGE
}

case ${1:-} in
  -h | --help)
    usage
    exit 0
    ;;
  "" | -*) usage_error ;;
esac
(($# == 1)) || usage_error
require_tty

snapshots=/persist/.snapshots
target=$(realpath -m -- "$1")
# /home is kept as /persist/home, which is where the snapshots have it
case $target in
  "$snapshots" | "$snapshots"/*) die "that's the snapshots themselves" ;;
  /persist/?*) rel=${target#/persist/} ;;
  /home/?*) rel=home/${target#/home/} ;;
  *) die "$target isn't in /home or on /persist. For another kept path, give where it's kept, such as /persist/var/lib/bluetooth" ;;
esac

# the snapshots that have it, newest first, as "<number>  <date>"
found=()
while read -r n; do
  sudo test -e "$snapshots/$n/snapshot/$rel" || continue
  # snapper writes the date in UTC
  when=$(sudo sed -n 's:.*<date>\(.*\)</date>.*:\1:p' "$snapshots/$n/info.xml" 2>/dev/null || true)
  if [[ -n $when ]]; then
    when=$(date -d "$when UTC" '+%a %F %H:%M' 2>/dev/null || echo "$when")
  else
    when="(no date)"
  fi
  found+=("$n  $when")
done < <(sudo find "$snapshots" -mindepth 1 -maxdepth 1 -name '[0-9]*' -printf '%f\n' | sort -rn)
((${#found[@]})) || die "no snapshot has $target; they go back 4 weeks"

choice=$(printf '%s\n' "${found[@]}" | gum choose --header "Bring back $target as it was in which snapshot?") || exit 0
n=${choice%% *}
aside="/persist/$rel.before-restore-$(date +%Y%m%d-%H%M%S)"
# as you know the path: your home folder through /home
shown=$aside
[[ $rel == home/* ]] && shown=/${aside#/persist/}
sudo test -d "$(dirname "/persist/$rel")" ||
  die "the folder it was in, $(dirname "$target"), is gone too; restore that instead"

echo "This puts back $target as it was in snapshot $n (${choice#*  })."
if sudo test -e "/persist/$rel" || sudo test -L "/persist/$rel"; then
  echo "What's there now is moved to $shown, not deleted."
fi
ask "Restore it?" || exit 0

if sudo test -e "/persist/$rel" || sudo test -L "/persist/$rel"; then
  sudo mv -- "/persist/$rel" "$aside"
fi
# -a keeps the owner and permissions it had, so a file in your home folder is still yours
sudo cp -a -- "$snapshots/$n/snapshot/$rel" "/persist/$rel"
echo "Restored $target from snapshot $n."
