# shellcheck shell=bash

# straight from a pipe, so the text never sits in a temp file
# shellcheck disable=SC2329 # not every command calls it
write_root_file() {
  printf '%s\n' "$2" | sudo install -D -m 600 -o root -g root /dev/stdin "$1"
}

# For a backup: it has to outlive this disk, so not in memory and not on the disk it's a backup of
# shellcheck disable=SC2329 # not every command calls it
check_offline_destination() {
  local dir=$1 src fstype luks=
  fstype=$(findmnt -no FSTYPE -T "$dir")
  case $fstype in
    tmpfs | ramfs) die "$dir is in memory and won't survive a reboot; use a USB stick or another disk" ;;
  esac
  luks=$(sudo cryptsetup status cryptroot 2>/dev/null | awk '$1 == "device:" { print $2 }') || luks=
  src=$(findmnt -no SOURCE -T "$dir")
  src=${src%%\[*}
  # lsblk read whole first: cut off by grep -q stopping early, pipefail would count it as no match
  if [[ -b $luks && -b $src ]] && grep -qxF "$luks" <<<"$(lsblk -nslpo NAME "$src")"; then
    die "$dir is on the encrypted disk itself; use a USB stick or another disk"
  fi
  if [[ ! -b $src ]]; then
    echo "warning: $dir is on $src ($fstype), make sure that's not this disk" >&2
  fi
}
