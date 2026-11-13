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
secret_files() {
  find "$1" -name .git -prune -o \( -name '*.key' -o -name '*.pem' -o -name '*.p12' -o -name '*.pfx' \
    -o -name '*.creds' -o -name '*.kdbx' -o -name 'id_rsa' -o -name 'id_ecdsa' -o -name 'id_ed25519' \
    -o -name '.env' -o -name '.env.*' -o -name 'secrets.nix' -o -name passwords \) -print 2>/dev/null || true
}

# shellcheck disable=SC2329
refuse_secret_files() {
  local dir=$1 found
  [[ ${EPHEMERAL_ALLOW_SECRET_FILES:-} == 1 ]] && return 0
  # a path: flake copies the whole folder into the Nix store, .gitignore or not
  found=$(secret_files "$dir")
  [[ -n $found ]] || return 0
  printf '%s\n' "$found" | sed 's/^/  /' >&2
  die "these look like secrets. A rebuild copies everything in $dir into the Nix store, where any user can read it.
Move them out, for example to /persist/etc/<name> owned by root with mode 600, then run this again.
To rebuild with them anyway: EPHEMERAL_ALLOW_SECRET_FILES=1"
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
