#!/usr/bin/env bash

set -euo pipefail

if ! command -v gum >/dev/null; then
  echo "Need gum on PATH (rebuild so controld-setup is installed)." >&2
  exit 1
fi

FLAKE_DIR=${FLAKE_DIR:-/persist/etc/nixos}
SETTINGS=$(settings_json "$FLAKE_DIR")
PASS_SETTINGS="$FLAKE_DIR/settings.from-pass.json"
ID_FILE=/persist/etc/controld-resolver

flag_in() {
  local file=$1
  [[ -f $file ]] || return 0
  jq -r 'if has("useControlD") then .useControlD | tostring else empty end' "$file"
}

set_flag() {
  local file=$1 value=$2
  [[ $value == true || $value == false ]] || die "bad flag value"
  # shellcheck disable=SC2016 # $v is jq's
  jq_edit "$file" --argjson v "$value" '.useControlD = $v'
}
current_id() {
  local id
  if ! sudo test -f "$ID_FILE"; then
    return 0
  fi
  id=$(sudo cat "$ID_FILE")
  id=${id//[$' \t\r\n']/}
  printf '%s' "$id"
}

write_id() {
  local id=$1 tmp
  [[ $id =~ ^[A-Za-z0-9_-]+$ ]] || die "resolver id must be letters, digits, _ or -"
  tmp=$(mktemp)
  printf '%s\n' "$id" >"$tmp"
  sudo install -m 600 -o root -g root "$tmp" "$ID_FILE"
  rm -f "$tmp"
}

show_status() {
  local flag id pass_flag
  flag=$(flag_in "$SETTINGS")
  id=$(current_id || true)
  pass_flag=$(flag_in "$PASS_SETTINGS")
  {
    printf 'settings.json: useControlD = %s\n' "${flag:-missing}"
    if [[ -n $id ]]; then
      printf 'resolver id: %s\n' "$id"
    else
      printf '%s\n' "resolver id: not set"
    fi
    if [[ -n $pass_flag ]]; then
      printf 'settings.from-pass.json: useControlD = %s\n' "$pass_flag"
    fi
  } | gum style --border rounded --padding "0 1" --border-foreground 240
}

set_existing_flag() {
  local file=$1 value=$2
  [[ -n $(flag_in "$file") ]] || return 0
  set_flag "$file" "$value"
}

set_id() {
  local id current
  current=$(current_id || true)
  id=$(gum input --header "Control D resolver id" --value "$current" --placeholder "your-resolver-id") || return 0
  id=$(printf '%s' "$id" | tr -d '[:space:]')
  [[ -z $id ]] && return 0
  if [[ ! $id =~ ^[A-Za-z0-9_-]+$ ]]; then
    gum style --foreground 1 "Id must be letters, digits, _ or -"
    return 1
  fi
  gum confirm "Write the id and set useControlD = true?" || return 0
  write_id "$id"
  set_flag "$SETTINGS" true
  set_existing_flag "$PASS_SETTINGS" true
  gum style --foreground 2 "Wrote $ID_FILE and enabled useControlD"
}

disable_controld() {
  gum confirm "Set useControlD = false? The id file stays." || return 0
  set_flag "$SETTINGS" false
  set_existing_flag "$PASS_SETTINGS" false
  gum style --foreground 2 "useControlD = false"
}

show_status
echo

action=$(gum choose --header "Control D" \
  "Set resolver id" \
  "Disable" \
  "Quit") || exit 0

case $action in
  "Set resolver id") set_id ;;
  "Disable") disable_controld ;;
  *) exit 0 ;;
esac

echo
gum style --bold "Next:"
gum style "  cd $FLAKE_DIR"
gum style "  sudo nixos-rebuild switch --flake path:.#nixos"
