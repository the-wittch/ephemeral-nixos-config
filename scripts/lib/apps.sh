# shellcheck shell=bash
# The rules for apps.json, with no screens. host-builder.nix applies the same ones at a rebuild,
# and the installer when it writes the file: an app ticked by default is picked unless apps.json
# has it as -<name>, and an app for one desktop is only offered on that one.

# called on its own, not in $( ), so a bad file stops the command
# shellcheck disable=SC2329 # not every command calls it
apps_check() {
  [[ -f $1 ]] || return 0
  jq -e 'type == "array" and all(.[]; type == "string")' "$1" >/dev/null ||
    die "$1 has to be a list of app names"
}

# <catalog> <apps.json>: the picked apps, one per line, those for other desktops included
# shellcheck disable=SC2329 # not every command calls it
apps_picked() {
  local entries='[]'
  [[ -f $2 ]] && entries=$(<"$2")
  # shellcheck disable=SC2016 # jq's variables
  jq -rn --argjson e "$entries" --slurpfile c "$1" '
    ($e | map(select(startswith("-") | not))) as $listed
    | ($e | map(select(startswith("-")) | .[1:])) as $unpicked
    | ($c[0] | to_entries | map(select(.value.default) | .key)) - $unpicked
    | $listed + . | unique | .[]'
}

# <catalog> <desktop> [category]: the apps offered there, by label
# shellcheck disable=SC2329 # not every command calls it
apps_offered() {
  # shellcheck disable=SC2016
  jq -r --arg c "${3:-}" --arg d "$2" 'to_entries
    | map(select(($c == "" or .value.category == $c)
      and (.value.desktops == [] or $d == "" or (.value.desktops | index($d)))))
    | sort_by(.value.label | ascii_downcase) | .[].key' "$1"
}

# <catalog> <desktop>: the categories with anything offered there
# shellcheck disable=SC2329 # not every command calls it
apps_categories() {
  # shellcheck disable=SC2016
  jq -r --arg d "$2" '[.[] | select(.desktops == [] or $d == "" or (.desktops | index($d))) | .category]
    | unique | .[]' "$1"
}

# <catalog>, the picked apps on standard input: apps.json, with -<name> for each unticked default
# shellcheck disable=SC2329 # not every command calls it
apps_file() {
  # shellcheck disable=SC2016
  jq -Rn --slurpfile c "$1" '[inputs | select(. != "")] as $picked
    | ($c[0] | to_entries | map(select(.value.default) | .key)) as $defaults
    | $picked + ($defaults - $picked | map("-" + .)) | unique'
}
