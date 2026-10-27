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
esac

dest=$1
[[ ! -e $dest ]] || die "$dest already exists"
dir=$(dirname -- "$dest")
[[ -d $dir ]] || die "no directory $dir"
dir=$(cd -- "$dir" && pwd)

luks=$(sudo cryptsetup status cryptroot | awk '$1 == "device:" { print $2 }')
[[ -b $luks ]] || die "could not find the device behind cryptroot"

src=$(findmnt -no SOURCE -T "$dir")
src=${src%%\[*}
fstype=$(findmnt -no FSTYPE -T "$dir")
case $fstype in
  tmpfs | ramfs) die "$dir is in memory and won't survive a reboot; use a USB stick or another disk" ;;
esac
if [[ -b $src ]] && lsblk -nslpo NAME "$src" | grep -qxF "$luks"; then
  die "$dir is on the encrypted disk itself; use a USB stick or another disk"
fi
if [[ ! -b $src ]]; then
  echo "warning: $dir is on $src ($fstype), make sure that's not this disk" >&2
fi

tmp=$(mktemp -d)
trap 'sudo rm -rf "$tmp"' EXIT
sudo cryptsetup luksHeaderBackup "$luks" --header-backup-file "$tmp/header.img"
sudo cryptsetup isLuks "$tmp/header.img" || die "the backup doesn't look like a LUKS header"
sudo install -m 600 -o "$(id -u)" -g "$(id -g)" "$tmp/header.img" "$dest"
sync -f "$dest"

echo "Wrote $dest ($(stat -c %s "$dest") bytes) from $luks"
echo "sha256: $(sha256sum "$dest" | cut -d' ' -f1)"
echo "Keep it off this machine. Restore with:"
echo "  sudo cryptsetup luksHeaderRestore $luks --header-backup-file <file>"
