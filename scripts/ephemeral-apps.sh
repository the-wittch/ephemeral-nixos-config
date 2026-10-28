#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
ephemeral-apps
Pick extra apps by category. The picks are saved to apps.json next to
settings.json, then the system is rebuilt. Run it again to add or remove apps.
USAGE
}

case ${1:-} in
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *)
    usage >&2
    exit 2
    ;;
esac

[[ $EUID -ne 0 ]] || die "run ephemeral-apps as your user; Flatpaks are installed for you"
[[ -n ${CATALOG:-} && -f $CATALOG ]] || die "no app catalog"

FLAKE_DIR=${FLAKE_DIR:-/persist/etc/nixos}
APPS="$FLAKE_DIR/apps.json"
[[ -f $FLAKE_DIR/flake.nix ]] || die "no flake at $FLAKE_DIR (set FLAKE_DIR)"

declare -A picked=() before=()
if [[ -f $APPS ]]; then
  jq -e 'type == "array" and all(.[]; type == "string")' "$APPS" >/dev/null ||
    die "$APPS has to be a list of app names"
  while IFS= read -r id; do
    picked[$id]=1
    before[$id]=1
  done < <(jq -r '.[]' "$APPS")
fi

row() {
  jq -r --arg id "$1" '.[$id] |
    "\(.label)  \(.description)"
    + (if .unfree then " · unfree" else "" end)
    + (if .flatpak then " · flatpak" else "" end)
    + (if .warn then " · read the warning" else "" end)' "$CATALOG"
}

ids_in() {
  jq -r --arg c "$1" 'to_entries | map(select(.value.category == $c)) | sort_by(.value.label | ascii_downcase) | .[].key' "$CATALOG"
}

pick_category() {
  local category=$1 id line out
  local -a ids=() rows=() selected=()
  local -A by_row=()
  while IFS= read -r id; do
    line=$(row "$id")
    ids+=("$id")
    rows+=("$line")
    by_row[$line]=$id
    [[ -z ${picked[$id]:-} ]] || selected+=("$line")
  done < <(ids_in "$category")

  local -a preselect=()
  if ((${#selected[@]})); then
    preselect=(--selected "$(
      IFS=,
      echo "${selected[*]}"
    )")
  fi
  out=$(printf '%s\n' "${rows[@]}" |
    gum choose --no-limit --height 20 --header "$category: space to tick, enter when done" "${preselect[@]}") || return 0

  for id in "${ids[@]}"; do
    unset "picked[$id]"
  done
  while IFS= read -r line; do
    [[ -z $line ]] || picked[${by_row[$line]}]=1
  done <<<"$out"
}

mapfile -t categories < <(jq -r '[.[].category] | unique | .[]' "$CATALOG")

gum style --bold --foreground 212 "Extra apps"
gum style --foreground 240 "Steam, VS Code, Brave and VLC come with \"extras\": true in settings.json."
echo

while true; do
  menu=()
  for c in "${categories[@]}"; do
    n=0
    while IFS= read -r id; do
      [[ -z ${picked[$id]:-} ]] || n=$((n + 1))
    done < <(ids_in "$c")
    menu+=("$c ($n)")
  done
  choice=$(gum choose --header "Pick a category" "${menu[@]}" "Review and save" "Quit without saving") || exit 0
  case $choice in
    "Review and save") break ;;
    "Quit without saving") exit 0 ;;
    *) pick_category "${choice% (*}" ;;
  esac
done

added=()
removed=()
for id in "${!picked[@]}"; do
  [[ -n ${before[$id]:-} ]] || added+=("$id")
done
for id in "${!before[@]}"; do
  [[ -n ${picked[$id]:-} ]] || removed+=("$id")
done

if ((${#added[@]} == 0 && ${#removed[@]} == 0)); then
  echo "Nothing changed."
  exit 0
fi

name() {
  jq -r --arg id "$1" '.[$id].label // $id' "$CATALOG"
}

{
  for id in "${added[@]}"; do
    printf '+ %s\n' "$(name "$id")"
  done
  for id in "${removed[@]}"; do
    printf -- '- %s\n' "$(name "$id")"
  done
} | gum style --border rounded --padding "0 1" --border-foreground 240

for id in "${added[@]}"; do
  warn=$(jq -r --arg id "$id" '.[$id].warn // empty' "$CATALOG")
  [[ -z $warn ]] || gum style --foreground 214 "$(name "$id"): $warn"
done

gum confirm "Save these changes?" || exit 0

tmp=$(mktemp)
if ((${#picked[@]})); then
  printf '%s\n' "${!picked[@]}" | sort | jq -R . | jq -s . >"$tmp"
else
  echo '[]' >"$tmp"
fi
if [[ -w $FLAKE_DIR ]]; then
  install -m 644 "$tmp" "$APPS"
else
  sudo install -m 644 "$tmp" "$APPS"
fi
rm -f "$tmp"
gum style --foreground 2 "Saved $APPS"

if gum confirm "Rebuild now?"; then
  ephemeral-update
  systemctl --user start ephemeral-flatpaks.service || true
else
  echo "Rebuild later with: ephemeral-update"
fi
