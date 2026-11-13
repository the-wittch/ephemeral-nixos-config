# shellcheck shell=bash
# shellcheck disable=SC2016 # the fakes are written out as they are, expanded when they run
# Runs the helper scripts against fake curl, nh, nix, sudo and chpasswd, and checks what they
# did. Called by flake/tests/scripts.nix with SCRIPTS pointing at scripts/.
set -euo pipefail

work=$(mktemp -d)
fakes=$work/bin
mkdir -p "$fakes"
calls=$work/calls
export CALLS=$calls ROOT=$work/root
export PATH=$fakes:$PATH

fake() {
  printf '#!%s\n%s\n' "$(command -v bash)" "$2" >"$fakes/$1"
  chmod +x "$fakes/$1"
}
fake curl '[[ -z ${FAKE_OFFLINE:-} ]] || exit 7; printf "{\"tag_name\": \"%s\"}\n" "$FAKE_LATEST"'
fake nh 'echo "nh $*" >>"$CALLS"'
fake nix 'echo "nix $*" >>"$CALLS"'
fake chpasswd 'echo "chpasswd $(cat)" >>"$CALLS"'
# runs the command as the test user, with /persist moved under $ROOT and install's owner dropped
fake sudo '
args=()
skip=0
for a in "$@"; do
  if ((skip)); then skip=0; continue; fi
  case $a in -o | -g) skip=1; continue ;; esac
  args+=("${a//\/persist/$ROOT/persist}")
done
[[ ${args[0]} == env ]] && args=("${args[@]:1}") && [[ ${args[0]} == PATH=* ]] && args=("${args[@]:1}")
exec "${args[@]}"'

failures=0
pass() { echo "ok: $1"; }
fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

tool() {
  cat "$SCRIPTS/lib.sh" "$SCRIPTS/$1.sh" >"$work/$1"
  echo "$work/$1"
}
update=$(tool ephemeral-update)
passwd=$(tool ephemeral-passwd)

# answers on a terminal, as the scripts only ask when there is one
on_tty() {
  local input=$1
  shift
  printf '%b' "$input" | script -qec "$(printf '%q ' "$@")" /dev/null >"$work/out" 2>&1
}

flake_at() {
  rm -rf "$work/flake" && mkdir -p "$work/flake"
  printf 'inputs.ephemeral.url = "github:the-wittch/ephemeral-nixos-config/%s";\n' "$1" >"$work/flake/flake.nix"
  : >"$work/flake/flake.lock"
  : >"$calls"
}
pinned() { grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' "$work/flake/flake.nix"; }

export FLAKE_DIR=$work/flake HOME=$work/home

flake_at v4.0.0
FAKE_LATEST=v4.0.1 on_tty 'y\n' bash "$update" || true
if [[ $(pinned) == v4.0.1 ]] && grep -q 'nix flake update ephemeral' "$calls" && grep -q '^nh os switch' "$calls"; then
  pass "update: a newer release is offered, and yes moves the pin, updates the lock and rebuilds"
else fail "update: moving to a newer release"; fi

flake_at v4.0.0
FAKE_LATEST=v4.0.1 on_tty 'n\n' bash "$update" || true
if [[ $(pinned) == v4.0.0 ]] && ! grep -q 'flake update' "$calls" && grep -q '^nh os switch' "$calls"; then
  pass "update: no keeps the pin and still rebuilds"
else fail "update: saying no"; fi

for latest in v3.9.0 'v4.0.1; reboot' v4.0; do
  flake_at v4.0.0
  FAKE_LATEST=$latest on_tty 'y\n' bash "$update" || true
  if [[ $(pinned) == v4.0.0 ]] && ! grep -q 'is out' "$work/out"; then
    pass "update: $latest isn't offered"
  else fail "update: $latest was offered"; fi
done

flake_at v4.0.0
FAKE_LATEST=v5.0.0 on_tty 'n\n' bash "$update" || true
if grep -q 'new major version' "$work/out"; then
  pass "update: a new major version says to read its Breaking section"
else fail "update: no warning for a major version"; fi

flake_at v4.0.0
FAKE_OFFLINE=1 on_tty '' bash "$update" || true
if grep -q '^nh os switch' "$calls"; then
  pass "update: offline, it rebuilds what's pinned"
else fail "update: offline"; fi

flake_at v4.0.0
mkdir -p "$work/flake/modules" && : >"$work/flake/modules/deploy.key"
if ! FAKE_LATEST=v4.0.0 on_tty '' bash "$update" && ! grep -q '^nh' "$calls" && grep -q 'deploy.key' "$work/out"; then
  pass "update: a key file in the flake stops the rebuild"
else fail "update: a key file in the flake was rebuilt into the store"; fi
: >"$calls"
EPHEMERAL_ALLOW_SECRET_FILES=1 FAKE_LATEST=v4.0.0 on_tty '' bash "$update" || true
if grep -q '^nh os switch' "$calls"; then
  pass "update: EPHEMERAL_ALLOW_SECRET_FILES=1 rebuilds anyway"
else fail "update: the override"; fi

flake_at v4.0.0
bash "$update" --check >"$work/out" 2>&1 || true
if grep -q '^nh os build path:' "$calls" && ! grep -q 'nh os switch' "$calls"; then
  pass "update --check builds without switching"
else fail "update --check"; fi

flake_at v4.0.0
bash "$update" --previous >"$work/out" 2>&1 || true
if grep -qx 'nh os rollback' "$calls" && ! grep -q 'nh os switch' "$calls"; then
  pass "update --previous rolls back and builds nothing"
else fail "update --previous"; fi

flake_at v4.0.0
mkdir -p "$work/installed" && : >"$work/installed/flake.nix"
EPHEMERAL_INSTALLED_DIR=$work/installed bash "$update" --as-installed >"$work/out" 2>&1 || true
if grep -q "^nh os switch path:$work/installed " "$calls" && [[ $(pinned) == v4.0.0 ]]; then
  pass "update --as-installed rebuilds the installed copy and leaves the config alone"
else fail "update --as-installed"; fi
: >"$calls"
if ! EPHEMERAL_INSTALLED_DIR=$work/none bash "$update" --as-installed >"$work/out" 2>&1 && ! grep -q '^nh' "$calls"; then
  pass "update --as-installed without a copy says so and builds nothing"
else fail "update --as-installed without a copy"; fi

flake_at v4.0.0
if ! bash "$update" --bogus >/dev/null 2>&1 && ! grep -q '^nh' "$calls"; then
  pass "update with an unknown option builds nothing"
else fail "update with an unknown option"; fi

flake_at v4.0.0
fake curl '
case $* in
  *CHANGELOG.md*) printf "# Changelog\n\n## 5.0.0\n\n### Breaking\n\n- the thing changed\n\n## 4.0.0\n\n- old\n" ;;
  *) printf "{\"tag_name\": \"%s\"}\n" "$FAKE_LATEST" ;;
esac'
FAKE_LATEST=v5.0.0 on_tty 'n\n' bash "$update" || true
if grep -q 'the thing changed' "$work/out" && ! grep -q '^  - old' "$work/out" && grep -q 'a new major version?' "$work/out"; then
  pass "update shows the changelog since the pinned release, and names a new major version in the question"
else fail "update's changelog"; fi

user=$(id -un)
password_file() {
  mkdir -p "$ROOT/persist/passwords"
  printf 'old-hash\n' >"$ROOT/persist/passwords/$user"
  : >"$calls"
}
unchanged() { [[ $(cat "$ROOT/persist/passwords/$user") == old-hash ]] && ! grep -q chpasswd "$calls"; }

password_file
on_tty 'one\ntwo\n' bash "$passwd" || true
if unchanged; then pass "passwd: passwords that don't match change nothing"; else fail "passwd: a mismatch changed the file"; fi

password_file
on_tty '\n\n' bash "$passwd" || true
if unchanged; then pass "passwd: an empty password changes nothing"; else fail "passwd: an empty password changed the file"; fi

password_file
fake mkpasswd 'echo oops'
on_tty 'hunter22\nhunter22\n' bash "$passwd" || true
rm "$fakes/mkpasswd"
if unchanged; then pass "passwd: a broken hash changes nothing"; else fail "passwd: a broken hash was written"; fi

password_file
on_tty 'hunter22\nhunter22\n' bash "$passwd" || true
hash=$(cat "$ROOT/persist/passwords/$user")
if [[ $hash == "\$y\$"* ]] && [[ $(stat -c %a "$ROOT/persist/passwords/$user") == 600 ]] && grep -qF "chpasswd $user:$hash" "$calls"; then
  pass "passwd: a matching password is written as a yescrypt hash, 600, and applied"
else fail "passwd: writing a good password"; fi

if ((failures)); then
  echo "$failures failed" >&2
  exit 1
fi
