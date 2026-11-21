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

# A server's host key for unlocking over SSH, and the copy of it the boot loader puts in the
# initrd. The boot loader reads that while it installs, before the new system could make it, so
# it's made here first. With Secure Boot on and a TPM, the copy is sealed to Secure Boot's state
# (PCR 7), so the one on the unencrypted boot partition only opens on this machine. Sealed again
# at every rebuild, since a firmware update can change that state.
# shellcheck disable=SC2154,SC2329 # the initrd_ssh_ names come from the prelude
make_initrd_ssh_key() {
  [[ $(setting server 2>/dev/null) == true ]] || return 0
  if ! sudo test -e "$initrd_ssh_key"; then
    echo "Making the host key for unlocking this server over SSH at boot."
    sudo install -d -m 700 "$(dirname "$initrd_ssh_key")"
    sudo ssh-keygen -q -t ed25519 -N '' -C initrd -f "$initrd_ssh_key"
  fi
  if secure_boot_on && tpm_present; then
    if sudo systemd-creds encrypt --with-key=tpm2 --tpm2-device=auto --tpm2-pcrs=7 \
      --name="$initrd_ssh_key_name" "$initrd_ssh_key" "$initrd_ssh_boot_key.new" &&
      sudo mv -f "$initrd_ssh_boot_key.new" "$initrd_ssh_boot_key"; then
      return 0
    fi
    echo "warning: couldn't seal the SSH key for unlocking at boot with the TPM, so its copy on the boot partition isn't sealed" >&2
  fi
  sudo install -m 600 "$initrd_ssh_key" "$initrd_ssh_boot_key"
}
