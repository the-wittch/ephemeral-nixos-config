#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
luks-header-backup <file>
Copy the LUKS header of the root disk to <file>, which must be on another disk.
USAGE
}

case ${1:-} in
  "" | -h | --help)
    usage
    [[ -n ${1:-} ]] && exit 0
    exit 2
    ;;
  -*) usage_error ;;
esac

dest=$1
[[ ! -e $dest ]] || die "$dest already exists"
dir=$(dirname -- "$dest")
[[ -d $dir ]] || die "no directory $dir"
dir=$(cd -- "$dir" && pwd)

luks=$(sudo cryptsetup status cryptroot | awk '$1 == "device:" { print $2 }')
[[ -b $luks ]] || die "could not find the device behind cryptroot"

check_offline_destination "$dir"

tmp=$(mktemp -d)
trap 'sudo rm -rf "$tmp"' EXIT
sudo cryptsetup luksHeaderBackup "$luks" --header-backup-file "$tmp/header.img"
sudo cryptsetup isLuks "$tmp/header.img" || die "the backup doesn't look like a LUKS header"
sudo install -m 600 -o "$(id -u)" -g "$(id -g)" "$tmp/header.img" "$dest"
sync -f "$dest"

# for ephemeral-doctor, which can't see the stick
printf '%s %s\n' "$(date +%F)" "$dest" | sudo install -D -m 644 /dev/stdin /persist/etc/ephemeral/luks-header-backup

echo "Wrote $dest ($(stat -c %s "$dest") bytes) from $luks"
echo "sha256: $(sha256sum "$dest" | cut -d' ' -f1)"
echo "Keep it off this machine. Restore with:"
echo "  sudo cryptsetup luksHeaderRestore $luks --header-backup-file <file>"
