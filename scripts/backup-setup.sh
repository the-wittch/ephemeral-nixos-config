#!/usr/bin/env bash
# shellcheck disable=SC2154 # the backup_ names come from the prelude

set -euo pipefail

usage() {
  cat <<'USAGE'
backup-setup [--from-pass [pass://VAULT/ITEM/FIELD]]
backup-setup add LABEL REPOSITORY
backup-setup remove LABEL
Set up scheduled backups. Without a command it makes what's missing: root's SSH key and the
passphrase, both in /persist/etc/borg and readable only by root, and a first repository in
backup.json next to settings.json. --from-pass takes the passphrase from Proton Pass, by
default the password of the borg item in the Personal vault.
A repository is ssh://user@host:port/./path, as a storage box or BorgBase gives it, or a folder.
USAGE
}

from_pass=
cmd=
case ${1:-} in
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  --from-pass)
    from_pass=${2:-pass://Personal/borg/password}
    [[ $from_pass == pass://*/*/* ]] || die "--from-pass takes pass://VAULT/ITEM/FIELD"
    ;;
  add)
    (($# == 3)) || usage_error
    cmd=add
    ;;
  remove)
    (($# == 2)) || usage_error
    cmd=remove
    ;;
  *) usage_error ;;
esac

flake=$(require_flake)
json=$flake/backup.json

repositories() {
  if [[ -f $json ]]; then
    jq -c '.[]' "$json"
  fi
}

save() {
  local out
  out=$(jq "$@" "$(if [[ -f $json ]]; then echo "$json"; else echo /dev/null; fi)") || die "could not update $json"
  printf '%s\n' "$out" | write_flake_file "$json" 644
}

add() {
  local label=$1 path=$2
  [[ $label =~ ^${backup_label_re}$ ]] || die "a label is letters, digits, _ and -, such as storagebox"
  [[ $path =~ ^${backup_repo_re}$ ]] ||
    die "$path isn't a repository: ssh://user@host:port/./path, as a storage box or BorgBase gives it, or a folder"
  if [[ -f $json ]] && jq -e --arg l "$label" 'any(.[]; .label == $l)' "$json" >/dev/null; then
    die "there's already a repository called $label; backup-setup remove $label first"
  fi
  # shellcheck disable=SC2016 # $l and $p are jq's
  save -n --arg l "$label" --arg p "$path" '(input? // []) + [{label: $l, path: $p}]'
  echo "Added $label to $json."
}

case $cmd in
  add)
    add "$2" "$3"
    echo "ephemeral-update puts it in the schedule."
    exit 0
    ;;
  remove)
    if [[ ! -f $json ]] || ! jq -e --arg l "$2" 'any(.[]; .label == $l)' "$json" >/dev/null; then
      die "there's no repository called $2"
    fi
    # shellcheck disable=SC2016 # $l is jq's
    save --arg l "$2" 'map(select(.label != $l))'
    echo "Removed $2 from $json; the backups already there stay. ephemeral-update takes it off the schedule."
    exit 0
    ;;
esac

if [[ -z $from_pass ]] && ! sudo test -s "$backup_dir/passphrase"; then
  require_tty
fi
sudo install -d -m 0700 -o root -g root "$backup_dir"
if ! sudo test -s "$backup_dir/ssh_key"; then
  sudo ssh-keygen -q -t ed25519 -N "" -C "backup@$(</proc/sys/kernel/hostname)" -f "$backup_dir/ssh_key"
fi

if sudo test -s "$backup_dir/passphrase"; then
  echo "The passphrase is already in $backup_dir/passphrase."
elif [[ -n $from_pass ]]; then
  command -v pass-cli >/dev/null || die "pass-cli isn't installed"
  # straight from pass-cli into the file, so it's never in a variable or on a command line
  pass-cli item view "$from_pass" | tr -d '\r' | sed -z 's/\n$//' |
    sudo install -m 0600 -o root -g root /dev/stdin "$backup_dir/passphrase.new"
  sudo test -s "$backup_dir/passphrase.new" || {
    sudo rm -f "$backup_dir/passphrase.new"
    die "nothing came from $from_pass; is pass-cli logged in?"
  }
  sudo mv "$backup_dir/passphrase.new" "$backup_dir/passphrase"
else
  read -rsp "A passphrase for the backups: " first && echo
  read -rsp "Again: " second && echo
  [[ -n $first && $first == "$second" ]] || die "they're empty or don't match"
  printf '%s' "$first" | sudo install -m 0600 -o root -g root /dev/stdin "$backup_dir/passphrase"
  first='' second=''
fi

if [[ -z $(repositories) && -t 0 ]]; then
  echo
  read -r -p "Where to back up (ssh://user@host:port/./path or a folder; empty for later): " path
  if [[ -n $path ]]; then
    read -r -p "A short name for it [backup]: " label
    add "${label:-backup}" "$path"
  fi
fi

echo
if [[ -n $(repositories) ]]; then
  echo "Backing up to:"
  repositories | jq -r '"  \(.label)  \(.path)"'
else
  echo "No repository yet: backup-setup add LABEL REPOSITORY."
fi
echo
echo "Root's SSH key, to add at the storage box or BorgBase:"
echo "  $(sudo cat "$backup_dir/ssh_key.pub")"
echo
echo "Then:"
echo "  ephemeral-update                                         # puts the backups on the schedule"
echo "  sudo borgmatic repo-create --encryption repokey-blake2   # once, for a new repository"
echo "  sudo systemctl start borgmatic                           # the first backup, now"
echo
echo "Keep the passphrase somewhere other than this machine: without it, the backups can't be read."
