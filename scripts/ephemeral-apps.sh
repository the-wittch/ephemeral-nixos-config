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
  *) usage_error ;;
esac

[[ $EUID -ne 0 ]] || die "run ephemeral-apps as your user; Flatpaks are installed for you"
[[ -n ${CATALOG:-} && -f $CATALOG ]] || die "no app catalog"
require_tty
flake=$(require_flake)
APPS="$flake/apps.json"

desktop=$(setting desktop)
apps_check "$APPS"
declare -A picked=() before=()
while IFS= read -r id; do
  picked[$id]=1
  before[$id]=1
done < <(apps_picked "$CATALOG" "$APPS")

row() {
  jq -r --arg id "$1" '.[$id] |
    "\(.label)  \(.description)"
    + (if .unfree then " · unfree" else "" end)
    + (if .flatpak then " · flatpak" else "" end)
    + (if .warn then " · read the warning" else "" end)' "$CATALOG"
}

ids_in() { apps_offered "$CATALOG" "$desktop" "$1"; }

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

mapfile -t categories < <(apps_categories "$CATALOG" "$desktop")

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

content=$(printf '%s\n' "${!picked[@]}" | apps_file "$CATALOG")
printf '%s\n' "$content" | write_flake_file "$APPS" 644
gum style --foreground 2 "Saved $APPS"

if gum confirm "Rebuild now?"; then
  ephemeral-update
  systemctl --user start ephemeral-flatpaks.service || true
else
  echo "Rebuild later with: ephemeral-update"
fi
