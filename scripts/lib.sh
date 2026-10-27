# shellcheck shell=bash

# shellcheck disable=SC2329
die() {
  echo "error: $*" >&2
  exit 1
}

# shellcheck disable=SC2329
jq_edit() {
  local file=$1 tmp mode
  shift
  [[ -w $file ]] || die "$file is not writable"
  tmp=$(mktemp "$file.XXXXXX")
  if ! jq "$@" "$file" >"$tmp"; then
    rm -f "$tmp"
    die "could not update $file"
  fi
  mode=$(stat -c %a "$file")
  chmod "$mode" "$tmp"
  mv -f "$tmp" "$file"
}

# shellcheck disable=SC2329
settings_json() {
  local dir=$1
  if [[ -f $dir/settings.json ]]; then
    printf '%s\n' "$dir/settings.json"
    return 0
  fi
  if [[ -f $dir/settings.nix ]]; then
    die "$dir/settings.nix has to be converted to settings.json first:
  cd $dir && nix eval --json --file settings.nix | jq . > settings.json && rm settings.nix"
  fi
  die "missing $dir/settings.json"
}
