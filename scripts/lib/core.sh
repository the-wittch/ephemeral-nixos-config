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

# controld_id_re comes from modules/settings/_rules.nix; packages.nix puts it in front of each command
# shellcheck disable=SC2154,SC2329
valid_controld_id() {
  [[ $1 =~ ^${controld_id_re}$ ]]
}
