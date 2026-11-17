# shellcheck shell=bash

# shellcheck disable=SC2329 # not every command calls it
die() {
  echo "error: $*" >&2
  exit 1
}

# for an option the command doesn't know; each command defines its own usage
# shellcheck disable=SC2329 # not every command calls it
usage_error() {
  usage >&2
  exit 2
}

# gum and read both need one; without it they fail, and the command would carry on or stop
# quietly with exit 0
# shellcheck disable=SC2329 # not every command calls it
require_tty() {
  [[ -t 0 ]] || die "$(basename "$0") asks its questions in a terminal, so run it in one"
}

# without a terminal the answer is no
# shellcheck disable=SC2329 # not every command calls it
ask() {
  local answer
  [[ -t 0 ]] || return 1
  read -r -p "$1 [y/N] " answer
  [[ ${answer:-n} =~ ^[Yy] ]]
}

# controld_id_re comes from modules/settings/_rules.nix, by way of modules/packages/_prelude.nix
# shellcheck disable=SC2154,SC2329
valid_controld_id() {
  [[ $1 =~ ^${controld_id_re}$ ]]
}

# A gum menu of the values given for a setting, shown as they're named in
# modules/settings/_choices.nix; prints the value picked. Args: setting, header, current value,
# then the values in order.
# shellcheck disable=SC2154,SC2329
pick_setting() {
  local key=$1 header=$2 current=$3 v picked
  shift 3
  picked=$(for v in "$@"; do printf '%s\n' "${menu_label["$key/$v"]}"; done |
    gum choose --header "$header" --selected "${menu_label["$key/$current"]:-}") || return 1
  for v in "$@"; do
    [[ $picked == "${menu_label["$key/$v"]}" ]] && printf '%s\n' "$v"
  done
  return 0
}
