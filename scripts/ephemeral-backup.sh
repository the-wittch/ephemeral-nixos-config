#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
ephemeral-backup <folder>
Save what a reinstall needs and git doesn't keep: settings.json, hardware-configuration.nix,
apps.json, smb-shares.json, the Control D id, SMB and Wi-Fi passwords, and the SSH host key.
They go into one file encrypted with a passphrase you pick, so a lost stick gives nothing away.
Your home folder isn't in it; back that up with Vorta or Pika Backup.
USAGE
}

case ${1:-} in
  "" | -h | --help)
    usage
    [[ -n ${1:-} ]] && exit 0
    exit 2
    ;;
esac

FLAKE_DIR=${FLAKE_DIR:-/persist/etc/nixos}
dir=$1
[[ -d $dir ]] || die "no folder $dir"
case $(findmnt -no FSTYPE -T "$dir") in
  tmpfs | ramfs) die "$dir is in memory and won't survive a reboot; use a USB stick or another disk" ;;
esac
[[ -t 0 ]] || die "ephemeral-backup needs a terminal to ask for the passphrase"

out="$dir/ephemeral-backup-$(hostname)-$(date +%F).tar.age"
[[ ! -e $out ]] || die "$out already exists"

paths=()
for p in "$FLAKE_DIR"/{settings.json,hardware-configuration.nix,apps.json,smb-shares.json} \
  /persist/etc/controld-resolver /persist/etc/smb /persist/etc/NetworkManager/system-connections \
  /persist/etc/ssh; do
  if sudo test -e "$p"; then
    paths+=("$p")
  fi
done
((${#paths[@]})) || die "found nothing to save"

echo "Saving:"
printf '  %s\n' "${paths[@]}"
echo "Pick a passphrase, and keep it somewhere other than this machine."
# age reads the passphrase from the terminal, so the archive can come in on stdin
sudo tar -C / -cf - "${paths[@]#/}" | age -p -o "$out"
sync -f "$out"

echo
echo "Wrote $out ($(du -h "$out" | cut -f1))."
echo "To restore after a reinstall:"
echo "  age -d $(basename "$out") | sudo tar -C / -xf -"
echo "  ephemeral-update"
