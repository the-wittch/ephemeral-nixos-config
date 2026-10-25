# shellcheck shell=bash
# prepended to the packaged scripts in apps.nix

# not every command uses every helper
# shellcheck disable=SC2329
die() {
  echo "error: $*" >&2
  exit 1
}

# body of a nix double-quoted string
# shellcheck disable=SC2329
nix_escape() {
  local s=$1
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//\$/\\$}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  s=${s//$'\t'/\\t}
  printf '%s' "$s"
}
