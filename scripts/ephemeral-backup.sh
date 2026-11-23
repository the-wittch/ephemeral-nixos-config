#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
ephemeral-backup <folder>
Save what a reinstall needs and git doesn't keep: settings.json, hardware-configuration.nix,
apps.json, smb-shares.json, backup.json, the Control D id, SMB and Wi-Fi passwords, the SSH host
key, the scheduled backups' passphrase and key, Syncthing's web page password, and the Secure
Boot keys.
They go into one file encrypted with a passphrase you pick, so a lost stick gives nothing away.
Your home folder isn't in it; scheduled backups (backup-setup) or Vorta take care of that.
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

flake=$(flake_dir)
dir=$1
[[ -d $dir ]] || die "no folder $dir"
check_offline_destination "$dir"
require_tty

out="$dir/ephemeral-backup-$(</proc/sys/kernel/hostname)-$(date +%F).tar.age"
[[ ! -e $out ]] || die "$out already exists"

paths=()
for p in "$flake"/{settings.json,hardware-configuration.nix,apps.json,smb-shares.json,backup.json} \
  /persist/etc/controld-resolver /persist/etc/smb /persist/etc/borg /persist/etc/syncthing \
  /persist/etc/NetworkManager/system-connections \
  /persist/etc/ssh /persist/var/lib/sbctl; do
  if sudo test -e "$p"; then
    paths+=("$p")
  fi
done
((${#paths[@]})) || die "found nothing to save"

echo "Saving:"
printf '  %s\n' "${paths[@]}"
echo "Pick a passphrase, and keep it somewhere other than this machine."
# written under another name until it's complete, so a stopped backup isn't mistaken for one
partial=$out.partial
trap 'rm -f "$partial"' EXIT
# age reads the passphrase from the terminal, so the archive can come in on stdin
sudo tar -C / -cf - "${paths[@]#/}" | age -p -o "$partial"
sync -f "$partial"
mv -f "$partial" "$out"

echo
echo "Wrote $out ($(du -h "$out" | cut -f1))."
echo "To restore after a reinstall:"
echo "  nix run nixpkgs#age -- -d $(basename "$out") | sudo tar -C / -xf -"
echo "  ephemeral-update"
