# shellcheck shell=bash
# The rules for apps.json, with no screens. host-builder.nix applies the same ones at a rebuild,
# and the installer when it writes the file: an app ticked by default, on every desktop or on the
# ones defaultOn names, is picked unless apps.json has it as -<name>, and an app for one desktop
# is only offered on that one. Without a desktop (desktop "none") only the terminal apps are
# offered, and only those among the defaults.

# called on its own, not in $( ), so a bad file stops the command
# shellcheck disable=SC2329 # not every command calls it
apps_check() {
  [[ -f $1 ]] || return 0
  jq -e 'type == "array" and all(.[]; type == "string")' "$1" >/dev/null ||
    die "$1 has to be a list of app names"
}

# <catalog> <apps.json> [desktop]: the picked apps, one per line, those for other desktops included
# shellcheck disable=SC2329 # not every command calls it
apps_picked() {
  local entries='[]'
  [[ -f $2 ]] && entries=$(<"$2")
  # shellcheck disable=SC2016 # jq's variables
  jq -rn --argjson e "$entries" --slurpfile c "$1" --arg d "${3:-}" '
    ($e | map(select(startswith("-") | not))) as $listed
    | ($e | map(select(startswith("-")) | .[1:])) as $unpicked
    | ($c[0] | to_entries | map(select((.value.default or ((.value.defaultOn // []) | index($d) != null)) and ($d != "none" or .value.category == "Terminal")) | .key)) - $unpicked
    | $listed + . | unique | .[]'
}

# <catalog> <desktop> [category]: the apps offered there, by label
# shellcheck disable=SC2329 # not every command calls it
apps_offered() {
  # shellcheck disable=SC2016
  jq -r --arg c "${3:-}" --arg d "$2" 'to_entries
    | map(select(($c == "" or .value.category == $c)
      and (if $d == "none" then .value.category == "Terminal"
        else .value.desktops == [] or $d == "" or (.value.desktops | index($d)) end)))
    | sort_by(.value.label | ascii_downcase) | .[].key' "$1"
}

# <catalog> <desktop>: the categories with anything offered there, in the order of
# app_categories, from modules/apps/_categories.nix
# shellcheck disable=SC2154,SC2329 # app_categories comes from the prelude; not every command calls it
apps_categories() {
  local present c
  # shellcheck disable=SC2016
  present=$(jq -r --arg d "$2" '[.[] | select(if $d == "none" then .category == "Terminal"
    else .desktops == [] or $d == "" or (.desktops | index($d)) end) | .category] | unique | .[]' "$1")
  for c in "${app_categories[@]}"; do
    if grep -qxF "$c" <<<"$present"; then echo "$c"; fi
  done
}

# <catalog> [desktop], the picked apps on standard input: apps.json, with -<name> for each
# unticked default
# shellcheck disable=SC2329 # not every command calls it
apps_file() {
  # shellcheck disable=SC2016
  jq -Rn --slurpfile c "$1" --arg d "${2:-}" '[inputs | select(. != "")] as $picked
    | ($c[0] | to_entries | map(select((.value.default or ((.value.defaultOn // []) | index($d) != null)) and ($d != "none" or .value.category == "Terminal")) | .key)) as $defaults
    | $picked + ($defaults - $picked | map("-" + .)) | unique'
}
