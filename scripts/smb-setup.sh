#!/usr/bin/env bash

set -euo pipefail

if ! command -v gum >/dev/null; then
  echo "Need gum on PATH (rebuild so smb-setup is installed)." >&2
  exit 1
fi

FLAKE_DIR=${FLAKE_DIR:-/persist/etc/nixos}
SHARES_JSON="$FLAKE_DIR/smb-shares.json"
CREDS_DIR=/persist/etc/smb
LIST_FILE="$CREDS_DIR/shares.list"

ensure_dirs() {
  sudo mkdir -p "$CREDS_DIR"
  sudo chmod 700 "$CREDS_DIR"
  if ! sudo test -f "$LIST_FILE"; then
    printf '%s\n' '# name|server|share|mountPoint' | sudo tee "$LIST_FILE" >/dev/null
    sudo chmod 600 "$LIST_FILE"
  fi
}

read_list() {
  sudo cat "$LIST_FILE" 2>/dev/null | grep -v '^#' | grep -v '^[[:space:]]*$' || true
}

write_shares_json() {
  local tmp name server share mount
  tmp=$(mktemp)
  while IFS="|" read -r name server share mount; do
    [[ -z ${name:-} ]] && continue
    jq -n \
      --arg server "$server" \
      --arg share "$share" \
      --arg mountPoint "$mount" \
      --arg credentials "$CREDS_DIR/${name}.creds" \
      '{ $server, $share, $mountPoint, $credentials }'
  done < <(read_list) | jq -s . >"$tmp"
  install -m 644 "$tmp" "$SHARES_JSON"
  rm -f "$tmp"
}

list_shares() {
  local rows
  rows=$(read_list)
  if [[ -z $rows ]]; then
    gum style --foreground 240 "No SMB shares configured yet."
    return
  fi
  printf '%s\n' "$rows" | while IFS='|' read -r name server share mount; do
    printf '%-12s //%s/%s → %s\n' "$name" "$server" "$share" "$mount"
  done | gum style --border rounded --padding "0 1" --border-foreground 240
}

add_share() {
  local name server share mount user pass creds line

  name=$(gum input --header "Share label (creds filename)" --placeholder "files") || return 0
  [[ -z $name ]] && return 0
  if [[ ! $name =~ ^[A-Za-z0-9_-]+$ ]]; then
    gum style --foreground 1 "Label must be alphanumeric / _ / -"
    return 1
  fi

  server=$(gum input --header "Server hostname or IP" --placeholder "nas.local") || return 0
  share=$(gum input --header "Share name" --placeholder "files") || return 0
  mount=$(gum input --header "Mount point" --placeholder "/mnt/files" --value "/mnt/${share}") || return 0
  user=$(gum input --header "Username" --placeholder "shareuser") || return 0
  pass=$(gum input --header "Password" --placeholder "••••••••" --password) || return 0

  if [[ -z $server || -z $share || -z $mount || -z $user || -z $pass ]]; then
    gum style --foreground 1 "All fields are required."
    return 1
  fi
  if [[ ! $server =~ ^[A-Za-z0-9._:-]+$ ]]; then
    gum style --foreground 1 "Server must be a hostname or IP."
    return 1
  fi
  if [[ ! $share =~ ^[A-Za-z0-9._\$\ -]+$ ]]; then
    gum style --foreground 1 "Share name: letters, digits, space, . _ - \$ only."
    return 1
  fi
  if [[ ! $mount =~ ^/[A-Za-z0-9._/-]+$ || $mount == *..* ]] ||
    [[ $mount != /mnt/?* && $mount != /media/?* && $mount != "$HOME"/?* ]]; then
    gum style --foreground 1 "Mount point must be under /mnt, /media, or $HOME."
    return 1
  fi
  if [[ $user == *$'\n'* || $pass == *$'\n'* ]]; then
    gum style --foreground 1 "Username and password must be one line."
    return 1
  fi

  if read_list | grep -q "^${name}|"; then
    gum confirm "Label '$name' exists. Replace it?" || return 0
    sudo sed -i "/^${name}|/d" "$LIST_FILE"
  fi

  creds="$CREDS_DIR/${name}.creds"
  printf 'username=%s\npassword=%s\n' "$user" "$pass" |
    sudo install -m 600 -o root -g root /dev/stdin "$creds"

  line="${name}|${server}|${share}|${mount}"
  printf '%s\n' "$line" | sudo tee -a "$LIST_FILE" >/dev/null
  sudo chmod 600 "$LIST_FILE"

  write_shares_json
  gum style --foreground 2 "Wrote $creds and $SHARES_JSON"
}

remove_share() {
  local rows choice name
  rows=$(read_list)
  [[ -z $rows ]] && {
    gum style --foreground 240 "Nothing to remove."
    return 0
  }
  choice=$(printf '%s\n' "$rows" | gum choose --header "Remove which share?") || return 0
  name=${choice%%|*}
  gum confirm "Remove '$name'?" || return 0
  sudo sed -i "/^${name}|/d" "$LIST_FILE"
  sudo rm -f "$CREDS_DIR/${name}.creds"
  write_shares_json
  gum style --foreground 2 "Removed $name"
}

ensure_dirs

gum style --bold --foreground 212 "SMB share setup"
echo
list_shares
echo

action=$(gum choose --header "What do you want to do?" \
  "Add / update share" \
  "Remove share" \
  "Regenerate smb-shares.json" \
  "Quit") || exit 0

case $action in
  "Add / update share") add_share ;;
  "Remove share") remove_share ;;
  "Regenerate smb-shares.json")
    write_shares_json
    gum style --foreground 2 "Regenerated $SHARES_JSON"
    ;;
  *) exit 0 ;;
esac

echo
gum style --bold "Next:"
gum style "  cd $FLAKE_DIR"
gum style "  sudo nixos-rebuild switch --flake path:.#nixos"
gum style "  findmnt /mnt/<share>"
