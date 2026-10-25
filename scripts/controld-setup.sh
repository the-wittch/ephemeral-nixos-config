#!/usr/bin/env bash
# controld-setup. id in /persist/etc/controld-resolver, flag in settings.nix.

set -euo pipefail

if ! command -v gum >/dev/null; then
  echo "Need gum on PATH (rebuild so controld-setup is installed)." >&2
  exit 1
fi

FLAKE_DIR=${FLAKE_DIR:-/persist/etc/nixos}
SETTINGS="$FLAKE_DIR/settings.nix"
PASS_SETTINGS="$FLAKE_DIR/settings.from-pass.nix"
ID_FILE=/persist/etc/controld-resolver

flag_in() {
  local file=$1 line
  [[ -f $file ]] || return 0
  line=$(grep -E '^[[:space:]]*useControlD[[:space:]]*=[[:space:]]*(true|false)' "$file" | head -1 || true)
  [[ -n $line ]] || return 0
  printf '%s' "$line" | sed -E 's/.*=[[:space:]]*(true|false).*/\1/'
}

set_flag() {
  local file=$1 value=$2 tmp mode
  [[ -f $file ]] || return 0
  [[ -w $file ]] || die "$file is not writable"
  [[ $value == true || $value == false ]] || die "bad flag value"
  tmp=$(mktemp)
  if grep -q -E '^[[:space:]]*useControlD[[:space:]]*=' "$file"; then
    sed -E "s/^([[:space:]]*useControlD[[:space:]]*=[[:space:]]*)(true|false)/\1${value}/" "$file" >"$tmp"
  else
    awk -v value="$value" '
      /^}[[:space:]]*$/ && !done {
        print "  useControlD = " value ";"
        done = 1
      }
      { print }
      END { if (!done) exit 1 }
    ' "$file" >"$tmp"
  fi
  grep -q -E "^[[:space:]]*useControlD[[:space:]]*=[[:space:]]*${value};" "$tmp" \
    || die "failed to set useControlD in $file"
  mode=$(stat -c %a "$file")
  install -m "$mode" "$tmp" "$file"
  rm -f "$tmp"
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
    printf 'settings.nix: useControlD = %s\n' "${flag:-missing}"
    if [[ -n $id ]]; then
      printf 'resolver id: %s\n' "$id"
    else
      printf '%s\n' "resolver id: not set"
    fi
    if [[ -n $pass_flag ]]; then
      printf 'settings.from-pass.nix: useControlD = %s\n' "$pass_flag"
    fi
  } | gum style --border rounded --padding "0 1" --border-foreground 240
}

set_existing_flag() {
  local file=$1 value=$2
  [[ -f $file ]] || return 0
  grep -q -E '^[[:space:]]*useControlD[[:space:]]*=' "$file" || return 0
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

[[ -f $SETTINGS ]] || die "missing $SETTINGS"
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
