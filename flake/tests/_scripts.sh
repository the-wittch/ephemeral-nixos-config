# shellcheck shell=bash
# shellcheck disable=SC2016 # the fakes are written out as they are, expanded when they run
# Runs the helper scripts against fake curl, nh, nix, sudo, systemctl, mkpasswd and chpasswd, and
# checks what they did. Called by flake/tests/scripts.nix with SCRIPTS pointing at scripts/
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
  cat "$SCRIPTS"/lib/{core,flake,release,files,apps}.sh "$SCRIPTS/$1.sh" >"$work/$1"
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

flake_at v4.0.0
mkdir -p "$work/flake/.git" && printf '[remote "origin"]\n\turl = git@github.com:me/machine.git\n' >"$work/flake/.git/config"
printf '{ services.openssh.enable = true; }\n' >"$work/flake/plain.nix"
if FAKE_LATEST=v4.0.0 on_tty '' bash "$update" && grep -q '^nh os switch' "$calls"; then
  pass "update: an ssh remote and ordinary modules don't look like secrets"
else fail "update: a flake with nothing secret in it was refused"; fi

flake_at v4.0.0
mkdir -p "$work/flake/.git" && printf '[remote "origin"]\n\turl = https://me:ghp_token@github.com/me/machine.git\n' >"$work/flake/.git/config"
if ! FAKE_LATEST=v4.0.0 on_tty '' bash "$update" && ! grep -q '^nh' "$calls" && grep -q 'remote URL' "$work/out"; then
  pass "update: a token in a git remote URL stops the rebuild"
else fail "update: a git remote with a token in it was rebuilt into the store"; fi

flake_at v4.0.0
printf -- '-----BEGIN OPENSSH %s-----\n' 'PRIVATE KEY' >"$work/flake/notes.txt"
printf 'token = "ghp_%s"\n' "$(printf 'a%.0s' {1..36})" >"$work/flake/module.nix"
if ! FAKE_LATEST=v4.0.0 on_tty '' bash "$update" && ! grep -q '^nh' "$calls" &&
  grep -q 'notes.txt' "$work/out" && grep -q 'module.nix' "$work/out"; then
  pass "update: a private key or a token inside an ordinary file stops the rebuild"
else fail "update: a private key or token in a file was rebuilt into the store"; fi

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

doctor=$(tool ephemeral-doctor)
fs=$work/fs
mkdir -p "$fs/etc/ephemeral" "$fs/var/lib/private/i2pd" "$fs/var/lib/private/foo" "$fs/var/lib/upower" \
  "$fs/var/lib/bluetooth" "$fs/var/lib/geoclue" "$fs/var/lib/systemd/timers" \
  "$fs/persist/var/lib/bluetooth" "$fs/persist/var/lib/docker" "$fs/persist/var/lib/systemd/timers"
printf '/var/lib/bluetooth/\n/var/lib/systemd/timers/\n/var/lib/private/i2pd/\n/etc/machine-id\n' >"$fs/etc/ephemeral/kept"
for f in private/i2pd/router private/foo/db upower/history bluetooth/keys systemd/timers/stamp lastlog; do
  echo x >"$fs/var/lib/$f"
done
ln -s private/i2pd "$fs/var/lib/i2pd"
echo x >"$fs/persist/var/lib/docker/image"
fake systemctl '
case $1 in
  list-units) printf "%s\n" bluetooth.service upower.service geoclue.service i2pd.service foo.service ;;
  show) printf "Id=bluetooth.service\nStateDirectory=bluetooth\nDynamicUser=no\n\nStateDirectory=upower\nId=upower.service\nDynamicUser=no\n\nId=geoclue.service\nDynamicUser=no\nStateDirectory=geoclue\n\nId=i2pd.service\nDynamicUser=yes\nStateDirectory=i2pd\n\nId=foo.service\nDynamicUser=yes\nStateDirectory=foo\n" ;;
esac'
EPHEMERAL_ROOT=$fs bash "$doctor" audit >"$work/out" 2>&1 || true
rm "$fakes/systemctl"
audit_says() { grep -qF -- "$1" "$work/out"; }
if audit_says "upower.service keeps its state in /var/lib/upower" && audit_says "foo.service keeps its state in /var/lib/private/foo"; then
  pass "audit: a service's state that isn't kept is reported, at its DynamicUser path too"
else fail "audit: unkept service state"; fi
if ! audit_says "bluetooth.service" && ! audit_says "i2pd.service" && ! audit_says "geoclue"; then
  pass "audit: kept state, kept DynamicUser state and empty folders aren't reported"
else fail "audit: reported state that's kept or empty"; fi
if audit_says "/var/lib/lastlog" && ! audit_says "/var/lib/systemd " && ! audit_says "/var/lib/i2pd "; then
  pass "audit: other unkept state is listed, folders holding kept ones and symlinks aren't"
else fail "audit: the other state in /var/lib"; fi
if audit_says "/persist/var/lib/docker" && ! audit_says "/persist/var/lib/bluetooth" && ! audit_says "/persist/var/lib/systemd"; then
  pass "audit: a folder on /persist nothing keeps any more is reported, ones in use aren't"
else fail "audit: leftovers on /persist"; fi

sb=$work/sb
vars=$sb/sys/firmware/efi/efivars
mkdir -p "$sb/etc/ephemeral" "$vars"
: >"$sb/etc/ephemeral/secure-boot"
printf '\x06\x00\x00\x00\x01' >"$vars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
flake_at v1.0.0
fake systemctl '[[ $1 == is-active ]] && exit 1; exit 0'
doctor_sb() { USER=alice EPHEMERAL_ROOT=$sb FLAKE_DIR=$work/flake FAKE_OFFLINE=1 bash "$doctor" >"$work/out" 2>&1 || true; }
doctor_sb
if grep -qF "Secure Boot is on" "$work/out" && grep -qF "no list of revoked bootloaders" "$work/out"; then
  pass "doctor: Secure Boot on with no dbx is a warning"
else fail "doctor: missed an empty dbx"; fi
head -c 4000 /dev/zero >"$vars/dbx-d719b2cb-3d3a-4596-a3bc-dad00e67656f"
doctor_sb
if grep -qF "Secure Boot is on" "$work/out" && ! grep -qF "no list of revoked bootloaders" "$work/out"; then
  pass "doctor: a dbx with entries isn't reported"
else fail "doctor: warned about a dbx that has entries"; fi
rm "$fakes/systemctl"

pubs=$(tool ssh-pubs-from-pass)
fake pass-cli 'echo "pass-cli $*" >>"$CALLS"; echo "[]"'
mkdir -p "$work/pubs"
printf '{"username": "alice", "passSshVault": "ossecrets"}\n' >"$work/pubs/settings.json"
: >"$calls"
FLAKE_DIR=$work/pubs bash "$pubs" --list >"$work/out" 2>&1 || true
if grep -q -- '--vault-name ossecrets ' "$calls"; then
  pass "ssh-pubs-from-pass: reads the vault the SSH agent uses from settings.json"
else fail "ssh-pubs-from-pass: ignored passSshVault"; fi
: >"$calls"
PASS_SSH_VAULT=other FLAKE_DIR=$work/pubs bash "$pubs" --list >"$work/out" 2>&1 || true
if grep -q -- '--vault-name other ' "$calls"; then
  pass "ssh-pubs-from-pass: PASS_SSH_VAULT still wins"
else fail "ssh-pubs-from-pass: PASS_SSH_VAULT"; fi

# scripts/lib on its own: runs the code with every library loaded, as the commands get them
lib() {
  bash -c "set -euo pipefail; $(cat "$SCRIPTS"/lib/{core,flake,release,files,apps}.sh); $1" >"$work/out" 2>&1 </dev/null
}

flake_at v4.2.0
if lib "[[ \$(pinned_release '$work/flake') == v4.2.0 ]]"; then
  pass "lib: pinned_release reads the tag flake.nix pins"
else fail "lib: pinned_release"; fi
for tag in v4.3.0 'v4.3.0; reboot' v4.3 latest ''; do
  want=""
  [[ $tag == v4.3.0 ]] && want=v4.3.0
  if FAKE_LATEST=$tag lib "[[ \$(latest_release) == '$want' ]]"; then
    pass "lib: latest_release gives '${want}' for a release tagged '$tag'"
  else fail "lib: latest_release with '$tag'"; fi
done
if FAKE_OFFLINE=1 lib '[[ -z $(latest_release) ]]'; then
  pass "lib: latest_release is empty offline"
else fail "lib: latest_release offline"; fi
newer=0
lib 'is_newer v4.10.0 v4.9.0 && is_newer v5.0.0 v4.9.9' || newer=1
lib '! is_newer v4.9.0 v4.10.0 && ! is_newer v4.9.0 v4.9.0 && ! is_newer "v5.0.0; x" v4.0.0 && ! is_newer "" v4.0.0 && ! is_newer v4.1.0 ""' || newer=1
if ((newer == 0)); then
  pass "lib: is_newer orders versions as numbers, and refuses anything that isn't vX.Y.Z"
else fail "lib: is_newer"; fi

if lib 'ask "go on?"'; then fail "lib: ask said yes without a terminal"; else
  pass "lib: ask is a no without a terminal"
fi
if ! lib require_tty && grep -q 'in a terminal' "$work/out"; then
  pass "lib: require_tty stops without a terminal and says why"
else fail "lib: require_tty"; fi

mkdir -p "$work/wf" && printf 'old\n' >"$work/wf/f.json" && chmod 640 "$work/wf/f.json"
if lib "printf 'new\n' | write_flake_file '$work/wf/f.json' 640" && [[ $(<"$work/wf/f.json") == new ]] &&
  [[ $(stat -c %a "$work/wf/f.json") == 640 ]] && [[ $(find "$work/wf" -type f | wc -l) == 1 ]]; then
  pass "lib: write_flake_file replaces the file, keeps the mode it's given and leaves nothing beside it"
else fail "lib: write_flake_file"; fi
if ! lib "printf 'newer\n' | write_flake_file '$work/wf/f.json' 999" && [[ $(<"$work/wf/f.json") == new ]] &&
  [[ $(find "$work/wf" -type f | wc -l) == 1 ]]; then
  pass "lib: a write_flake_file that fails leaves the file as it was, with no temp file"
else fail "lib: a failed write_flake_file"; fi
printf '{"a": 1}\n' >"$work/wf/s.json"
if ! lib "jq_edit '$work/wf/s.json' '.a |'" && [[ $(jq -c . "$work/wf/s.json") == '{"a":1}' ]]; then
  pass "lib: jq_edit with a broken filter leaves the file as it was"
else fail "lib: jq_edit with a broken filter"; fi
if lib "jq_edit '$work/wf/s.json' '.a = 2'" && [[ $(jq -c . "$work/wf/s.json") == '{"a":2}' ]]; then
  pass "lib: jq_edit edits the file"
else fail "lib: jq_edit"; fi

rm -rf "$work/sf" && mkdir -p "$work/sf"
if ! FLAKE_DIR=$work/sf lib 'flake=$(require_flake)' && grep -q "no flake at $work/sf" "$work/out"; then
  pass "lib: require_flake stops when there's no flake.nix"
else fail "lib: require_flake"; fi
: >"$work/sf/flake.nix"
printf '{"desktop": "gnome"}\n' >"$work/sf/settings.json"
if FLAKE_DIR=$work/sf lib '[[ $(require_flake) == '"$work/sf"' && $(setting desktop) == gnome && -z $(setting nothing) ]]'; then
  pass "lib: require_flake gives the folder, and setting reads settings.json"
else fail "lib: require_flake and setting"; fi
rm "$work/sf/settings.json" && : >"$work/sf/settings.nix"
if ! FLAKE_DIR=$work/sf lib 'd=$(setting desktop)' && grep -q 'settings.nix has to be converted' "$work/out"; then
  pass "lib: setting stops on a leftover settings.nix, as a rebuild does"
else fail "lib: setting with settings.nix"; fi

# a small catalog: two defaults, one of them for GNOME only, and one for Plasma only
cat >"$work/catalog.json" <<'JSON'
{
  "firefox": {"label": "Firefox", "category": "Browsers", "default": true, "desktops": []},
  "tweaks": {"label": "GNOME Tweaks", "category": "Utilities", "default": true, "desktops": ["gnome"]},
  "discover": {"label": "Discover", "category": "Utilities", "default": false, "desktops": ["plasma"]},
  "steam": {"label": "Steam", "category": "Gaming", "default": false, "desktops": []}
}
JSON
printf '["-firefox", "discover", "steam"]\n' >"$work/apps.json"
if lib "[[ \$(apps_picked '$work/catalog.json' '$work/apps.json' | paste -sd ' ') == 'discover steam tweaks' ]]"; then
  pass "lib: apps_picked has what apps.json lists and the defaults it doesn't untick"
else fail "lib: apps_picked: $(cat "$work/out")"; fi
if lib "[[ \$(apps_picked '$work/catalog.json' '$work/none.json' | paste -sd ' ') == 'firefox tweaks' ]]"; then
  pass "lib: apps_picked with no apps.json is the defaults"
else fail "lib: apps_picked without apps.json"; fi
if lib "[[ \$(apps_offered '$work/catalog.json' gnome Utilities) == tweaks && \$(apps_offered '$work/catalog.json' plasma Utilities) == discover && \$(apps_categories '$work/catalog.json' plasma | paste -sd ' ') == 'Browsers Gaming Utilities' ]]"; then
  pass "lib: an app for one desktop is only offered on that one"
else fail "lib: apps_offered and apps_categories"; fi
if lib "[[ \$(printf 'steam\ntweaks\n' | apps_file '$work/catalog.json' | jq -c .) == '[\"-firefox\",\"steam\",\"tweaks\"]' ]]"; then
  pass "lib: apps_file writes the picks, and -<name> for an unticked default"
else fail "lib: apps_file: $(cat "$work/out")"; fi
printf '{"not": "a list"}\n' >"$work/bad-apps.json"
if ! lib "apps_check '$work/bad-apps.json'" && grep -q 'has to be a list' "$work/out"; then
  pass "lib: apps_check stops on an apps.json that isn't a list"
else fail "lib: apps_check"; fi

fake findmnt 'case "$2 $FAKE_FSTYPE" in FSTYPE*) echo "$FAKE_FSTYPE" ;; SOURCE*) echo "$FAKE_SOURCE" ;; esac'
fake cryptsetup 'echo "  device:  /dev/fake-luks"'
if ! FAKE_FSTYPE=tmpfs FAKE_SOURCE=tmpfs lib "check_offline_destination '$work'" && grep -q 'in memory' "$work/out"; then
  pass "lib: check_offline_destination refuses a folder in memory"
else fail "lib: check_offline_destination with tmpfs"; fi
if FAKE_FSTYPE=fuse FAKE_SOURCE=remote: lib "check_offline_destination '$work'" && grep -q "make sure that's not this disk" "$work/out"; then
  pass "lib: check_offline_destination warns when it can't tell which disk a folder is on"
else fail "lib: check_offline_destination with an unknown source"; fi

# every command: --help works, an unknown option is refused before anything runs, and the ones
# with questions stop without a terminal instead of doing nothing and exiting 0
fake gum 'exit 0'
export CATALOG=$work/catalog.json
for name in ephemeral-update ephemeral-doctor ephemeral-setup ephemeral-apps ephemeral-backup ephemeral-passwd \
  ephemeral-report controld-setup smb-setup luks-header-backup settings-from-pass ssh-pubs-from-pass update-pass-cli; do
  cmd=$(tool "$name")
  if bash "$cmd" --help >"$work/out" 2>&1 </dev/null && [[ -s $work/out ]]; then
    pass "$name --help"
  else fail "$name --help"; fi
  : >"$calls"
  code=0
  bash "$cmd" --bogus >"$work/out" 2>&1 </dev/null || code=$?
  if ((code == 2)) && [[ ! -s $calls ]]; then
    pass "$name refuses an unknown option with exit 2, and runs nothing"
  else fail "$name with an unknown option exited $code"; fi
done
mkdir -p "$work/stick"
for name in ephemeral-setup ephemeral-apps ephemeral-passwd controld-setup smb-setup ephemeral-backup; do
  args=()
  [[ $name == ephemeral-backup ]] && args=("$work/stick")
  code=0
  FAKE_FSTYPE=ext4 FAKE_SOURCE=/dev/sdb1 bash "$(tool "$name")" "${args[@]}" >"$work/out" 2>&1 </dev/null || code=$?
  if ((code == 1)) && grep -q 'in a terminal' "$work/out"; then
    pass "$name stops without a terminal"
  else fail "$name without a terminal exited $code: $(head -c 200 "$work/out")"; fi
done
rm "$fakes/findmnt" "$fakes/cryptsetup" "$fakes/gum"
unset CATALOG

if ((failures)); then
  echo "$failures failed" >&2
  exit 1
fi
