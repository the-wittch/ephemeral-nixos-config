#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
ephemeral-apps
Pick apps by category; a few are ticked from the start. The picks are saved to
apps.json next to settings.json, and it offers to rebuild. Run it again to add or
remove apps.
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

desktop=$(jq -r '.desktop // empty' "$FLAKE_DIR/settings.json" 2>/dev/null || true)

# apps ticked by default are picked unless apps.json has them as -<name>
declare -A picked=() before=() unpicked=()
if [[ -f $APPS ]]; then
  jq -e 'type == "array" and all(.[]; type == "string")' "$APPS" >/dev/null ||
    die "$APPS has to be a list of app names"
  while IFS= read -r id; do
    if [[ $id == -* ]]; then
      unpicked[${id#-}]=1
    else
      picked[$id]=1
    fi
  done < <(jq -r '.[]' "$APPS")
fi
mapfile -t defaults < <(jq -r 'to_entries | map(select(.value.default)) | .[].key' "$CATALOG")
for id in "${defaults[@]}"; do
  [[ -n ${unpicked[$id]:-} ]] || picked[$id]=1
done
for id in "${!picked[@]}"; do
  before[$id]=1
done

row() {
  jq -r --arg id "$1" '.[$id] |
    "\(.label)  \(.description)"
    + (if .unfree then " · unfree" else "" end)
    + (if .flatpak then " · flatpak" else "" end)
    + (if .warn then " · read the warning" else "" end)' "$CATALOG"
}

ids_in() {
  jq -r --arg c "$1" --arg d "$desktop" 'to_entries
    | map(select(.value.category == $c and (.value.desktops == [] or $d == "" or (.value.desktops | index($d)))))
    | sort_by(.value.label | ascii_downcase) | .[].key' "$CATALOG"
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
    gum choose --no-limit --height 20 --header "$category: x to tick, enter when done" "${preselect[@]}") || return 0

  for id in "${ids[@]}"; do
    unset "picked[$id]"
  done
  while IFS= read -r line; do
    [[ -z $line ]] || picked[${by_row[$line]}]=1
  done <<<"$out"
}

mapfile -t categories < <(jq -r --arg d "$desktop" '[.[] | select(.desktops == [] or $d == "" or (.desktops | index($d))) | .category] | unique | .[]' "$CATALOG")

gum style --bold --foreground 212 "Apps"
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

lines=("${!picked[@]}")
for id in "${defaults[@]}"; do
  [[ -n ${picked[$id]:-} ]] || lines+=("-$id")
done
tmp=$(mktemp)
if ((${#lines[@]})); then
  printf '%s\n' "${lines[@]}" | sort | jq -R . | jq -s . >"$tmp"
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
