# shellcheck shell=bash

# shellcheck disable=SC2329 # not every command calls it
flake_dir() {
  printf '%s\n' "${FLAKE_DIR:-/persist/etc/nixos}"
}

# flake=$(require_flake): the flake folder, or the reason there isn't a usable one
# shellcheck disable=SC2329 # not every command calls it
require_flake() {
  local flake
  flake=$(flake_dir)
  if [[ ! -f $flake/flake.nix ]]; then
    [[ -d $flake && ! -r $flake ]] && die "can't read $flake; fix it with: sudo chmod 755 $flake"
    die "no flake at $flake (set FLAKE_DIR to use another)"
  fi
  printf '%s\n' "$flake"
}

# shellcheck disable=SC2329 # not every command calls it
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

# shellcheck disable=SC2329 # not every command calls it
setting() {
  local file
  file=$(settings_json "$(flake_dir)") || exit 1
  jq -r --arg k "$1" '.[$k] // empty' "$file"
}

# the installer leaves the flake to root
# shellcheck disable=SC2329 # not every command calls it
flake_needs_owner() {
  local dir=$1 f
  [[ -w $dir ]] || return 0
  for f in flake.nix flake.lock settings.json; do
    [[ ! -e $dir/$f || -w $dir/$f ]] || return 0
  done
  return 1
}

# Replaces <dest> with standard input, as one rename, so it's never half written. With sudo only
# when the folder or file still belongs to root.
# shellcheck disable=SC2329 # not every command calls it
write_flake_file() {
  local dest=$1 mode=$2 tmp
  if [[ -w $(dirname "$dest") && (! -e $dest || -w $dest) ]]; then
    tmp=$(mktemp "$dest.XXXXXX")
    trap 'rm -f "$tmp"' INT TERM
    if ! cat >"$tmp" || ! chmod "$mode" "$tmp" || ! mv -f "$tmp" "$dest"; then
      rm -f "$tmp"
      trap - INT TERM
      die "could not write $dest"
    fi
    trap - INT TERM
  else
    if ! sudo install -m "$mode" /dev/stdin "$dest.new" || ! sudo mv -f "$dest.new" "$dest"; then
      die "could not write $dest"
    fi
  fi
}

# jq's output is complete before anything is written, so a failed filter leaves the file as it was
# shellcheck disable=SC2329 # not every command calls it
jq_edit() {
  local file=$1 out
  shift
  [[ -w $file ]] || die "$file is not writable"
  out=$(jq "$@" "$file") || die "could not update $file"
  printf '%s\n' "$out" | write_flake_file "$file" "$(stat -c %a "$file")"
}

# shellcheck disable=SC2329 # not every command calls it
secret_files() {
  local dir=$1
  find "$dir" -name .git -prune -o \( -name '*.key' -o -name '*.pem' -o -name '*.p12' -o -name '*.pfx' \
    -o -name '*.creds' -o -name '*.kdbx' -o -name 'id_rsa' -o -name 'id_ecdsa' -o -name 'id_ed25519' \
    -o -name '.env' -o -name '.env.*' -o -name 'secrets.nix' -o -name passwords -o -name .git-credentials \) \
    -print 2>/dev/null || true
  # .git goes into the store too; a token in a remote URL ends up there
  if grep -qsE '^[[:space:]]*(push)?url[[:space:]]*=[[:space:]]*[a-z+]+://[^/@[:space:]]+@' "$dir/.git/config"; then
    printf '%s (a remote URL with a token or password in it)\n' "$dir/.git/config"
  fi
  grep -rlIE --exclude-dir=.git \
    -e 'BEGIN (RSA |OPENSSH |EC |DSA |ENCRYPTED )?PRIVATE KEY' -e 'AGE-SECRET-KEY-1[0-9A-Z]{50,}' \
    -e 'gh[pousr]_[A-Za-z0-9]{30,}' -e 'github_pat_[A-Za-z0-9_]{20,}' -e 'glpat-[A-Za-z0-9_-]{20,}' \
    -e 'tskey-[a-z]+-[A-Za-z0-9-]{10,}' -e 'AKIA[0-9A-Z]{16}' -e 'xox[abprs]-[A-Za-z0-9-]{10,}' \
    "$dir" 2>/dev/null || true
}

# shellcheck disable=SC2329 # not every command calls it
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
