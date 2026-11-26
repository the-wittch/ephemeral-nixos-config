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
  {
    cat "$PRELUDE" "$SCRIPTS/$1.sh"
  } >"$work/$1"
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

initrd_key=$ROOT/persist/etc/ssh/initrd/ssh_host_ed25519_key
flake_at v4.0.0
printf '{"server": false}\n' >"$work/flake/settings.json"
FAKE_OFFLINE=1 on_tty '' bash "$update" || true
first=
if [[ ! -e $initrd_key ]]; then
  printf '{"server": true}\n' >"$work/flake/settings.json"
  FAKE_OFFLINE=1 on_tty '' bash "$update" || true
  first=$(cat "$initrd_key.pub" 2>/dev/null) || true
  FAKE_OFFLINE=1 on_tty '' bash "$update" || true
fi
boot_key=$ROOT/persist/etc/ssh/initrd/boot-key
if [[ -n $first && $(stat -c %a "$initrd_key") == 600 && $(cat "$initrd_key.pub") == "$first" ]] &&
  cmp -s "$initrd_key" "$boot_key" && [[ $(stat -c %a "$boot_key") == 600 ]] && grep -q '^nh os switch' "$calls"; then
  pass "update: only a server gets a key for unlocking over SSH, made before the rebuild and kept after"
else fail "update: the key for unlocking a server over SSH"; fi

fake systemd-creds 'echo "systemd-creds $*" >>"$CALLS"; printf "sealed %s\n" "${*: -2:1}" >"${*: -1}"'
sealing=$work/sealing
mkdir -p "$sealing/dev" "$sealing/sys/firmware/efi/efivars"
: >"$sealing/dev/tpmrm0"
printf '\x06\x00\x00\x00\x01' >"$sealing/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
EPHEMERAL_ROOT=$sealing FAKE_OFFLINE=1 on_tty '' bash "$update" || true
if grep -q -- '--with-key=tpm2 .*--tpm2-pcrs=7 --name=initrd-ssh-host-key' "$calls" &&
  [[ $(cat "$boot_key") == "sealed $ROOT/persist/etc/ssh/initrd/ssh_host_ed25519_key" ]] &&
  [[ $(cat "$initrd_key.pub") == "$first" ]] && ! grep -q 'PRIVATE KEY' "$boot_key"; then
  pass "update: with Secure Boot and a TPM, the boot copy of a server's key is sealed to PCR 7"
else fail "update: sealing the boot copy of a server's key"; fi

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
# the same list as kept.json, everything set up as it says, so only the service checks speak
jq -n --arg u "$(id -un)" --arg g "$(id -gn)" '{version: 1, persistRoot: "/persist", resetSubvolume: "/root",
  filesystems: [{mountPoint: "/", fsType: "btrfs", subvolume: "/root"}],
  entries: ([["directory", "/var/lib/bluetooth"], ["directory", "/var/lib/systemd/timers"],
             ["directory", "/var/lib/private/i2pd"]]
            | map({kind: .[0], path: .[1], how: "bindmount", inInitrd: false, user: $u, group: $g, mode: "0755", declaredIn: []}))
    + [{kind: "file", path: "/etc/machine-id", how: "symlink", inInitrd: true, user: $u, group: $g, mode: "0644", declaredIn: []}]}' \
  >"$fs/etc/ephemeral/kept.json"
ln -s /persist/etc/machine-id "$fs/etc/machine-id"
mkdir -p "$fs/persist/var/lib/private/i2pd" "$fs/persist/etc"
jq -n '[{target: "/", source: "/dev/mapper/cryptroot[/root]", fsroot: "/root", fstype: "btrfs"},
    {target: "/persist", source: "/dev/mapper/cryptroot[/persist]", fsroot: "/persist", fstype: "btrfs"}]
  + (["/var/lib/bluetooth", "/var/lib/systemd/timers", "/var/lib/private/i2pd"]
     | map({target: ., source: "/dev/mapper/cryptroot[/persist\(.)]", fsroot: "/persist\(.)", fstype: "btrfs"}))
  | {filesystems: .}' >"$work/mounts.json"
fake findmnt '[[ $1 == -J ]] || exit 1; cat "$FAKE_MOUNTS"'
export FAKE_MOUNTS=$work/mounts.json
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
# the build runs as its own user, so the folders here aren't root's
if audit_says "{ directory = \"/var/lib/private/foo\"; mode = \"0700\"; configureParent = true; parent.mode = \"0700\"; }" &&
  audit_says "{ directory = \"/var/lib/upower\"; user = \"$(id -un)\"; group = \"$(id -gn)\"; mode = \"0755\"; }"; then
  pass "audit: the advice gives a folder's owner and mode, and /var/lib/private's for DynamicUser"
else fail "audit: advice $(grep -F 'to keep it' "$work/out")"; fi
rm "$fakes/findmnt"

# ephemeral-doctor persistence, on a machine made of files and a fake findmnt: kept /home, a
# bluetooth folder with the wrong mode, a libvirt folder that isn't mounted, a mount nothing
# declares, a kept link and a broken one, a share, firmware storage, and some awkward names
pf=$work/pf
u=$(id -un) g=$(id -gn)
mkdir -p "$pf/etc/ephemeral" "$pf/home/alice/Documents" "$pf/home/alice/.cache" "$pf/home/alice/Videos" \
  "$pf/persist/home/alice" "$pf/persist/etc" "$pf/persist/var/lib/bluetooth" "$pf/persist/var/lib/libvirt" \
  "$pf/persist/var/lib/docker" "$pf/var/lib/bluetooth" "$pf/var/lib/libvirt" "$pf/var/lib/docker" \
  "$pf/var/lib/systemd" "$pf/var/lib/locked/inside" "$pf/tmp" "$pf/mnt/nas" "$pf/srv/my files" \
  "$pf/persist/srv/my files" "$pf/sys/firmware/efi/efivars" "$pf/var/lib/borgmatic/checks/r1"
echo x >"$pf/home/alice/Documents/a"
: >"$pf/home/alice/Videos/.nobackup"
echo id >"$pf/persist/etc/machine-id"
ln -s /persist/etc/machine-id "$pf/etc/machine-id"
ln -s /persist/var/lib/systemd/random-seed "$pf/var/lib/systemd/random-seed"
: >"$pf/tmp/new"$'\n'"line"
: >"$pf/var/lib/borgmatic/checks/r1/repository"
chmod 755 "$pf/var/lib/bluetooth"
printf 'P sh\nR /home\nR /persist/etc\n! home/*/.cache\n' >"$pf/etc/ephemeral/backup-patterns.lst"
echo v5.1.0 >"$pf/etc/ephemeral/release"
jq -n --arg u "$u" --arg g "$g" '
  def dir($p; $mode; $from): {kind: "directory", path: $p, how: "bindmount", inInitrd: false, user: $u, group: $g, mode: $mode, declaredIn: [$from]};
  {version: 1, persistRoot: "/persist", resetSubvolume: "/root",
   filesystems: [{mountPoint: "/", fsType: "btrfs", subvolume: "/root"}, {mountPoint: "/persist", fsType: "btrfs", subvolume: "/persist"},
                 {mountPoint: "/nix", fsType: "btrfs", subvolume: "/nix"}, {mountPoint: "/var/log", fsType: "btrfs", subvolume: "/log"},
                 {mountPoint: "/boot", fsType: "vfat", subvolume: null}],
   entries: [dir("/home"; "0755"; "modules/persist.nix"), dir("/var/lib/bluetooth"; "0700"; "modules/hardware.nix"),
             dir("/var/lib/libvirt"; "0755"; "this machine'"'"'s flake: modules/virt.nix"), dir("/srv/my files"; "0755"; "modules/x.nix"),
             {kind: "file", path: "/etc/machine-id", how: "symlink", inInitrd: true, user: $u, group: $g, mode: "0644", declaredIn: ["modules/persist.nix"]},
             {kind: "file", path: "/var/lib/systemd/random-seed", how: "symlink", inInitrd: true, user: $u, group: $g, mode: "0644", declaredIn: ["modules/persist.nix"]}]}' \
  >"$pf/etc/ephemeral/kept.json"
mounts() {
  jq -n --arg root "$1" '
    def sub($t; $r): {target: $t, source: "/dev/mapper/cryptroot[\($r)]", fsroot: $r, fstype: "btrfs"};
    {filesystems: [sub("/"; $root), sub("/persist"; "/persist"), sub("/nix"; "/nix"), sub("/var/log"; "/log"),
      {target: "/boot", source: "/dev/vda1", fsroot: "/", fstype: "vfat"},
      sub("/home"; "/persist/home"), sub("/var/lib/bluetooth"; "/persist/var/lib/bluetooth"),
      sub("/var/lib/docker"; "/persist/var/lib/docker"), sub("/srv/my files"; "/persist/srv/my files"),
      {target: "/tmp", source: "tmpfs", fsroot: "/", fstype: "tmpfs"},
      {target: "/mnt/nas", source: "//nas/files", fsroot: "/", fstype: "cifs"},
      {target: "/sys/firmware/efi/efivars", source: "efivarfs", fsroot: "/", fstype: "efivarfs"}]}' >"$FAKE_MOUNTS"
}
mounts /root
fake findmnt '[[ $1 == -J ]] || exit 1; cat "$FAKE_MOUNTS"'
fake systemctl '[[ $* == "show -p Result --value borgmatic.service" ]] && echo success; exit 0'
fake journalctl 'echo "2026-11-23T10:00:00+0000 host systemd[1]: Finished borgmatic."'
chmod 000 "$pf/var/lib/locked"
before=$({ find "$pf" -printf "%p %m %s %T@\n" 2>/dev/null || true; } | sort)
persist() { EPHEMERAL_ROOT=$pf bash "$doctor" persistence "$@"; }
at() { jq -c --arg p "$1" '.paths[] | select(.path == $p)' "$work/p.json"; }
is() { [[ $(at "$1" | jq -r "$2") == "$3" ]]; }
code=0
persist --json --path /home/alice/Documents --path /home/alice/.cache --path /home/alice/Videos --path /tmp \
  --path / --path /var --path /var/lib/libvirt --path /var/lib/libvirt/images --path /mnt/nas \
  --path /sys/firmware/efi/efivars --path /etc/machine-id --path /var/lib/systemd/random-seed \
  --path "/srv/my files" --path "/tmp/new"$'\n'"line" --path /var/lib/locked/inside --path /nope \
  >"$work/p.json" 2>"$work/err" || code=$?
if ((code == 0)) && jq -e '.version == 1 and (.paths | length) == 16' "$work/p.json" >/dev/null; then
  pass "persistence --json: valid, version 1, a path each, exit 0"
else fail "persistence --json exited $code: $(head -c 300 "$work/err")"; fi
if is /home/alice/Documents .classification persistent && is /home/alice/Documents .inside_declared /home &&
  is /home/alice/Documents .survives_reboot true && is "/srv/my files" .classification persistent &&
  is "/srv/my files" .verified true; then
  pass "persistence: inside a kept bind mount is persistent, a name with a space too"
else fail "persistence: persistent paths $(at /home/alice/Documents)"; fi
if is /tmp .classification ephemeral && is /tmp .survives_reboot false && is /nope .classification ephemeral &&
  is /nope .exists no && is "/tmp/new"$'\n'"line" .classification ephemeral; then
  pass "persistence: tmpfs and the reset root are ephemeral, a missing path and a newline in a name too"
else fail "persistence: ephemeral paths $(at /tmp) $(at /nope)"; fi
if is / .classification mixed && is /var .classification mixed && is /var .own_classification ephemeral &&
  [[ $(at /var | jq '.kept_inside | length') == 3 ]]; then
  pass "persistence: a folder holding kept paths is mixed, and says which"
else fail "persistence: mixed $(at /var)"; fi
if is /var/lib/libvirt .classification unverified && is /var/lib/libvirt .verified false &&
  is /var/lib/libvirt/images .classification unverified && is /var/lib/libvirt .declared_in[0] "this machine's flake: modules/virt.nix"; then
  pass "persistence: declared but not mounted is unverified, inside it too, with the module that declared it"
else fail "persistence: unverified $(at /var/lib/libvirt)"; fi
if is /mnt/nas .classification unknown && is /sys/firmware/efi/efivars .classification unknown &&
  is /mnt/nas .survives_reboot null && is /var/lib/locked/inside .exists unknown; then
  pass "persistence: a share, firmware storage and an unreadable path are unknown, not guessed"
else fail "persistence: unknown $(at /mnt/nas) $(at /var/lib/locked/inside)"; fi
if is /etc/machine-id .classification persistent && is /etc/machine-id .verified true &&
  is /var/lib/systemd/random-seed .classification persistent && is /var/lib/systemd/random-seed .type link; then
  pass "persistence: a kept link is persistent, a broken one too, without following it"
else fail "persistence: links $(at /etc/machine-id) $(at /var/lib/systemd/random-seed)"; fi
if is /home/alice/Documents .backup_coverage included && is /home/alice/.cache .backup_coverage excluded &&
  is /home/alice/Videos .backup_coverage excluded && is /tmp .backup_coverage excluded &&
  is /etc/machine-id .backup_coverage included && is /etc/machine-id .backup_via /persist/etc/machine-id &&
  is /home/alice/.cache .classification persistent; then
  pass "persistence: backups are told apart from persistence: a ! line, a .nobackup, and a link's target"
else fail "persistence: backups $(at /home/alice/.cache) $(at /home/alice/Videos) $(at /etc/machine-id)"; fi
if jq -e '.backup == {configured: true, last_result: "success", last_success: "2026-11-23T10:00:00+0000", last_check: (.backup.last_check)}
    and (.backup.last_check | test("repository"))' "$work/p.json" >/dev/null; then
  pass "persistence: the last backup and check come from systemd and borgmatic"
else fail "persistence: backup status $(jq -c .backup "$work/p.json")"; fi
# the fields other tools can count on; a change here is a new version
if [[ $(jq -c 'keys' "$work/p.json") == '["as_root","backup","generated_at","paths","summary","system","truncated","version"]' ]] &&
  [[ $(jq -c '.paths[0] | keys' "$work/p.json") == '["backing","backup_coverage","backup_reason","backup_via","classification","declaration","declared","declared_in","exists","group","inside_declared","kept_inside","link","mechanism","mode","notes","own_classification","owner","path","survives_reboot","type","unknown_inside","verified"]' ]] &&
  jq -e '.summary | .persistent + .ephemeral + .mixed + .unknown + .unverified == .paths' "$work/p.json" >/dev/null; then
  pass "persistence --json: the documented fields, and a summary that adds up"
else fail "persistence --json fields: $(jq -c 'keys, (.paths[0] | keys)' "$work/p.json")"; fi
code=0
persist --audit >"$work/out" 2>&1 || code=$?
if ((code == 1)) && audit_says "✗ /var/lib/libvirt is declared, but isn't set up" &&
  audit_says "! /var/lib/bluetooth's owner or mode isn't what the config says" &&
  audit_says "! /var/lib/docker is kept, but the config doesn't say so" &&
  ! audit_says "random-seed's owner"; then
  pass "persistence --audit: critical, warnings and exit 1; a link's mode isn't compared"
else fail "persistence --audit exited $code: $(cat "$work/out")"; fi
persist --audit --json >"$work/a.json" 2>/dev/null || true
if jq -e '[.findings[].severity] | unique - ["critical", "warning", "informational", "unknown"] == []' "$work/a.json" >/dev/null &&
  jq -e '[.findings[] | select(.path == "/var/lib/libvirt" and .severity == "critical") | .evidence] | length == 1 and all(test("no mount"))' "$work/a.json" >/dev/null &&
  jq -e '[.findings[].severity] | . == (sort_by({critical: 0, warning: 1, informational: 2, unknown: 3}[.]))' "$work/a.json" >/dev/null &&
  jq -e '.findings[] | select(.path == "/var/lib/libvirt" and .severity == "informational") | .remediation | test("/persist/var/lib/libvirt")' "$work/a.json" >/dev/null &&
  jq -e '.findings[0] | keys == ["evidence", "explanation", "finding", "path", "remediation", "severity"]' "$work/a.json" >/dev/null; then
  pass "persistence --audit --json: each finding has its severity, evidence and fix"
else fail "persistence --audit --json: $(jq -c '.findings' "$work/a.json")"; fi
mounts /root-old
code=0
persist --audit >"$work/out" 2>&1 || code=$?
if ((code == 1)) && audit_says "✗ / is mounted from /root-old, not /root" && audit_says "--fix-root-reset"; then
  pass "persistence --audit: / from the wrong subvolume is critical"
else fail "persistence --audit with / moved: $(cat "$work/out")"; fi
# as test machines have it: / in memory, and /persist a disk of its own, mounted from its root
jq -n 'def bind($t): {target: $t, source: "/dev/vdb[\($t)]", fsroot: $t, fstype: "btrfs"};
  {filesystems: [{target: "/", source: "tmpfs", fsroot: "/", fstype: "tmpfs"},
    {target: "/persist", source: "/dev/vdb", fsroot: "/", fstype: "btrfs"},
    bind("/home"), bind("/var/lib/bluetooth")]}' >"$FAKE_MOUNTS"
persist --json --path /home/alice/Documents --path /var/lib/bluetooth --path / --path /tmp \
  --path /persist/home/alice >"$work/p.json" 2>/dev/null || true
if is /home/alice/Documents .classification persistent && is /var/lib/bluetooth .verified true &&
  is / .classification mixed && is /tmp .classification ephemeral &&
  is /persist/home/alice .backup_via /home/alice; then
  pass "persistence: /persist on a disk of its own is read from what's mounted there"
else fail "persistence with /persist on its own disk: $(at /var/lib/bluetooth) $(at /persist/home/alice)"; fi
mounts /root
persist --summary >"$work/out" 2>&1 || true
if audit_says "declared       6 (4 folders, 2 files)" && audit_says "set up now     5 of them; not: /var/lib/libvirt" &&
  audit_says "◐ MIXED       var/" && audit_says "  ● PERSISTENT  home/"; then
  pass "persistence: the summary counts what's declared and set up, and draws the tree"
else fail "persistence --summary: $(cat "$work/out")"; fi
if [[ $({ find "$pf" -printf "%p %m %s %T@\n" 2>/dev/null || true; } | sort) == "$before" ]]; then
  pass "persistence: nothing was changed by any of it"
else fail "persistence changed the files it read"; fi
chmod 755 "$pf/var/lib/locked"
rm "$fakes/findmnt" "$fakes/systemctl" "$fakes/journalctl"

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
: >"$sb/etc/ephemeral/tpm-unlock"
printf '\x06\x00\x00\x00\x00' >"$vars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
doctor_sb
if grep -qF "unlock with the TPM, but Secure Boot is off" "$work/out"; then
  pass "doctor: TPM unlock with Secure Boot off is reported"
else fail "doctor: missed TPM unlock with Secure Boot off"; fi
fake fwupdmgr '[[ -n ${FAKE_FW:-} ]] || exit 2; printf "%s\n" "$FAKE_FW"'
FAKE_FW='{"Devices": [{"Name": "System Firmware", "Plugin": "uefi_capsule", "Version": "2.16.0", "Releases": [{"Version": "2.19.0"}, {"Version": "2.18.0"}]}]}' doctor_sb
if grep -qF "firmware updates are waiting" "$work/out" && grep -qF "System Firmware 2.16.0 → 2.19.0" "$work/out" &&
  grep -qF "fwupdmgr update" "$work/out" && grep -qF "enroll the PIN again" "$work/out"; then
  pass "doctor: a waiting firmware update is listed with how to install it, and what it means for the TPM PIN"
else fail "doctor: a waiting firmware update"; fi
doctor_sb
if grep -qF "no firmware updates waiting" "$work/out" && ! grep -qF "firmware updates are waiting" "$work/out"; then
  pass "doctor: no firmware updates is said so"
else fail "doctor: no firmware updates"; fi
rm "$fakes/fwupdmgr" "$fakes/systemctl"

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

frompass=$(tool settings-from-pass)
fake pass-cli 'key=${3##*/}; case $key in controldResolver) exit 1 ;; *) echo "from-pass-$key" ;; esac'
mkdir -p "$work/frompass"
: >"$work/frompass/flake.nix"
printf '{"username": "alice", "usePassSettings": true}\n' >"$work/frompass/settings.json"
FLAKE_DIR=$work/frompass bash "$frompass" >"$work/out" 2>&1 || true
want=$(bash -c "$(cat "$PRELUDE")"'; printf "%s\n" "${pass_keys[@]}"' | sort)
if [[ $(jq -r 'keys[]' "$work/frompass/settings.from-pass.json" 2>/dev/null | sort) == "$want" ]] &&
  [[ $(jq -r .hostname "$work/frompass/settings.from-pass.json") == from-pass-hostname ]]; then
  pass "settings-from-pass: copies every key the loader takes from the Pass item"
else fail "settings-from-pass: wrote $(cat "$work/frompass/settings.from-pass.json" 2>/dev/null || cat "$work/out")"; fi

# scripts/lib on its own: runs the code with every library loaded, as the commands get them
lib() {
  bash -c "set -euo pipefail; $(cat "$PRELUDE"); $1" >"$work/out" 2>&1 </dev/null
}

fake gum 'cat >"$FAKE_MENU"; printf "%s\n" "$FAKE_PICK"'
if FAKE_MENU=$work/menu lib 'export FAKE_PICK=${menu_label["encryptedDns/quad9"]}; [[ $(pick_setting encryptedDns DNS none none quad9) == quad9 ]]' &&
  [[ $(wc -l <"$work/menu") == 2 ]]; then
  pass "lib: pick_setting shows the values given by their names and prints the one picked"
else fail "lib: pick_setting $(cat "$work/out")"; fi
rm "$fakes/gum"

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

fake systemd-cryptenroll 'echo "systemd-cryptenroll $*" >>"$CALLS"'
: >"$calls"
if lib 'tpm_enroll /dev/vda2' &&
  grep -qxF "systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes --wipe-slot=tpm2 /dev/vda2" "$calls"; then
  pass "lib: tpm_enroll binds to PCR 7 with a PIN, and replaces only an older TPM slot"
else fail "lib: tpm_enroll"; fi
: >"$calls"
if lib 'tpm_remove /dev/vda2' && grep -qxF "systemd-cryptenroll --wipe-slot=tpm2 /dev/vda2" "$calls"; then
  pass "lib: tpm_remove wipes the TPM slot and no other"
else fail "lib: tpm_remove"; fi
rm "$fakes/systemd-cryptenroll"
tr=$work/tpmroot
mkdir -p "$tr/dev" "$tr/sys/firmware/efi/efivars"
absent=0
EPHEMERAL_ROOT=$tr lib '! tpm_present && [[ -z $(efi_flag SecureBoot) ]]' || absent=1
: >"$tr/dev/tpmrm0"
printf '\x06\x00\x00\x00\x01' >"$tr/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
if ((absent == 0)) && EPHEMERAL_ROOT=$tr lib 'tpm_present && [[ $(efi_flag SecureBoot) == 1 ]]'; then
  pass "lib: tpm_present and efi_flag see the TPM and the firmware's Secure Boot state, and their absence"
else fail "lib: tpm_present or efi_flag"; fi
hidden=$work/hidden
mkdir -p "$hidden/sys/kernel/boot_params" "$hidden/sys/firmware/efi/efivars"
boot_params() { {
  head -c 492 /dev/zero
  printf '%b' "$1"
  head -c 100 /dev/zero
} >"$hidden/sys/kernel/boot_params/data"; }
boot_params '\x03'
if EPHEMERAL_ROOT=$hidden lib 'secure_boot_on' && boot_params '\x02' && ! EPHEMERAL_ROOT=$hidden lib 'secure_boot_on' &&
  EPHEMERAL_ROOT=$tr lib 'secure_boot_on'; then
  pass "lib: secure_boot_on reads the firmware, and the kernel's record when the firmware hides its variables"
else fail "lib: secure_boot_on"; fi
boot_params '\x03'
mkdir -p "$hidden/etc/ephemeral"
: >"$hidden/etc/ephemeral/secure-boot"
fake systemctl '[[ $1 == is-active ]] && exit 1; exit 0'
USER=alice EPHEMERAL_ROOT=$hidden FLAKE_DIR=$work/flake FAKE_OFFLINE=1 bash "$doctor" >"$work/out" 2>&1 || true
rm "$fakes/systemctl"
if grep -qF "Secure Boot is on" "$work/out" && grep -qF "can't be checked" "$work/out" && ! grep -qF "no list of revoked" "$work/out"; then
  pass "doctor: Secure Boot hidden from Linux but on is reported as on, and the dbx as unknown, not missing"
else fail "doctor: Secure Boot with hidden variables"; fi

srv=$work/server-root
mkdir -p "$srv/etc/ephemeral" "$srv/dev" "$srv/sys/firmware/efi/efivars" "$srv/persist/etc/ssh/initrd"
: >"$srv/etc/ephemeral/server"
: >"$srv/dev/tpmrm0"
printf '\x06\x00\x00\x00\x01' >"$srv/sys/firmware/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
doctor_srv() {
  USER=alice EPHEMERAL_ROOT=$srv FLAKE_DIR=$work/flake FAKE_OFFLINE=1 bash "$doctor" >"$work/out" 2>&1 || true
  grep -c "$1" "$work/out" || true
}
fake systemctl '[[ $1 == is-active ]] && exit 1; exit 0'
missing=$(doctor_srv "no key for unlocking")
printf -- '-----BEGIN a plain key\n' >"$srv/persist/etc/ssh/initrd/boot-key"
unsealed=$(doctor_srv "isn't sealed to the TPM, so")
printf 'sealed\n' >"$srv/persist/etc/ssh/initrd/boot-key"
sealed=$(doctor_srv "with its key sealed to the TPM")
rm "$fakes/systemctl"
if ((missing == 1 && unsealed == 1 && sealed == 1)); then
  pass "doctor: a server's key for unlocking over SSH: missing, unsealed with a TPM to seal it, and sealed"
else fail "doctor: a server's key for unlocking over SSH ($missing $unsealed $sealed)"; fi
backup=$(tool backup-setup)
flake_at v4.17.0
bjson=$work/flake/backup.json
box=ssh://u1@u1.your-storagebox.de:23/./borg
if bash "$backup" add storagebox "$box" >"$work/out" 2>&1 &&
  [[ $(jq -c . "$bjson") == "[{\"label\":\"storagebox\",\"path\":\"$box\"}]" ]] &&
  bash "$backup" add usb /run/media/alice/disk/borg >"$work/out" 2>&1 && [[ $(jq length "$bjson") == 2 ]]; then
  pass "backup-setup: adds repositories to backup.json"
else fail "backup-setup add: $(cat "$work/out")"; fi
refused=0
for args in "storagebox $box" "x ssh://host/;reboot" "x relative/folder" "a.b /mnt/borg" "x https://example.com/borg"; do
  # shellcheck disable=SC2086 # one argument per word
  if ! bash "$backup" add $args >"$work/out" 2>&1; then refused=$((refused + 1)); fi
done
if ((refused == 5)) && [[ $(jq length "$bjson") == 2 ]]; then
  pass "backup-setup: refuses a label that's taken, and labels and repositories that don't fit the rules"
else fail "backup-setup refused $refused of 5"; fi
if bash "$backup" remove usb >"$work/out" 2>&1 && [[ $(jq -r '.[].label' "$bjson") == storagebox ]] &&
  ! bash "$backup" remove usb >"$work/out" 2>&1; then
  pass "backup-setup: removes a repository, and says when there's none of that name"
else fail "backup-setup remove: $(cat "$work/out")"; fi
borg=$ROOT/persist/etc/borg
if on_tty 'correct horse\ncorrect horse\n' bash "$backup" && [[ $(cat "$borg/passphrase") == "correct horse" ]] &&
  [[ $(stat -c %a "$borg/passphrase") == 600 && $(stat -c %a "$borg") == 700 ]] &&
  grep -qF "$(cat "$borg/ssh_key.pub")" "$work/out"; then
  pass "backup-setup: makes root's key and keeps the typed passphrase root-only, and shows the key to add"
else fail "backup-setup: $(cat "$work/out")"; fi
key=$(cat "$borg/ssh_key.pub")
if on_tty '' bash "$backup" && [[ $(cat "$borg/ssh_key.pub") == "$key" ]] && grep -q "already in" "$work/out"; then
  pass "backup-setup: run again, it keeps the key and the passphrase"
else fail "backup-setup again: $(cat "$work/out")"; fi

bk=$work/backup-root
mkdir -p "$bk/etc/borgmatic" "$bk/persist/etc/borg"
: >"$bk/etc/borgmatic/config.yaml"
doctor_bk() {
  USER=alice EPHEMERAL_ROOT=$bk FLAKE_DIR=$work/flake FAKE_OFFLINE=1 bash "$doctor" >"$work/out" 2>&1 || true
  grep -c "$1" "$work/out" || true
}
fake systemctl '[[ $1 == is-failed ]] && exit "${FAKE_FAILED:-1}"; [[ $1 == is-active ]] && exit 1; exit 0'
nokey=$(doctor_bk "passphrase or SSH key is missing")
echo x >"$bk/persist/etc/borg/ssh_key"
echo x >"$bk/persist/etc/borg/passphrase"
fine=$(doctor_bk "scheduled backups are on$")
failed=$(FAKE_FAILED=0 doctor_bk "the last scheduled backup failed")
if ((nokey == 1 && fine == 1 && failed == 1)); then
  pass "doctor: scheduled backups without their passphrase, working, and after a failed run"
else fail "doctor: scheduled backups ($nokey $fine $failed)"; fi
off=$(doctor_bk "Flatpak")
mkdir -p "$bk/etc/systemd/user"
: >"$bk/etc/systemd/user/flatpak-update.timer"
fine=$(doctor_bk "Flatpak apps are updated once a week")
failed=$(FAKE_FAILED=0 doctor_bk "the last weekly Flatpak update failed")
rm "$fakes/systemctl"
if ((off == 0 && fine == 1 && failed == 1)); then
  pass "doctor: weekly Flatpak updates, off, working, and after a failed run"
else fail "doctor: Flatpak updates ($off $fine $failed)"; fi

if lib 'valid_controld_id abc-1_2 && ! valid_controld_id "a b" && ! valid_controld_id "x;y" && ! valid_controld_id ""'; then
  pass "lib: valid_controld_id takes the rule from the settings rules"
else fail "lib: valid_controld_id"; fi

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

# a small catalog: three defaults, one of them for GNOME only and one a terminal app, one app for
# Plasma only, and Passwords, which the config's order puts before Gaming and the alphabet after it
cat >"$work/catalog.json" <<'JSON'
{
  "firefox": {"label": "Firefox", "category": "Browsers", "default": true, "desktops": []},
  "tweaks": {"label": "GNOME Tweaks", "category": "Utilities", "default": true, "desktops": ["gnome"]},
  "discover": {"label": "Discover", "category": "Utilities", "default": false, "desktops": ["plasma"]},
  "steam": {"label": "Steam", "category": "Gaming", "default": false, "desktops": []},
  "htop": {"label": "htop", "category": "Terminal", "default": true, "desktops": []},
  "keepassxc": {"label": "KeePassXC", "category": "Passwords", "default": false, "desktops": []},
  "heroic": {"label": "Heroic", "category": "Gaming", "default": false, "defaultOn": ["handheld"], "desktops": []}
}
JSON
printf '["-firefox", "discover", "steam"]\n' >"$work/apps.json"
if lib "[[ \$(apps_picked '$work/catalog.json' '$work/apps.json' | paste -sd ' ') == 'discover htop steam tweaks' ]]"; then
  pass "lib: apps_picked has what apps.json lists and the defaults it doesn't untick"
else fail "lib: apps_picked: $(cat "$work/out")"; fi
if lib "[[ \$(apps_picked '$work/catalog.json' '$work/none.json' | paste -sd ' ') == 'firefox htop tweaks' ]]"; then
  pass "lib: apps_picked with no apps.json is the defaults"
else fail "lib: apps_picked without apps.json"; fi
if lib "[[ \$(apps_offered '$work/catalog.json' gnome Utilities) == tweaks && \$(apps_offered '$work/catalog.json' plasma Utilities) == discover && \$(apps_categories '$work/catalog.json' plasma | paste -sd ' ') == 'Browsers Passwords Gaming Terminal Utilities' ]]"; then
  pass "lib: an app for one desktop is only offered on that one, and the categories come in the config's order"
else fail "lib: apps_offered and apps_categories"; fi
if lib "[[ \$(printf 'steam\ntweaks\n' | apps_file '$work/catalog.json' | jq -c .) == '[\"-firefox\",\"-htop\",\"steam\",\"tweaks\"]' ]]"; then
  pass "lib: apps_file writes the picks, and -<name> for an unticked default"
else fail "lib: apps_file: $(cat "$work/out")"; fi
if lib "[[ \$(apps_picked '$work/catalog.json' '$work/none.json' handheld | paste -sd ' ') == 'firefox heroic htop tweaks' && \$(apps_picked '$work/catalog.json' '$work/none.json' plasma | paste -sd ' ') == 'firefox htop tweaks' && \$(printf 'firefox\nhtop\n' | apps_file '$work/catalog.json' handheld | jq -c .) == '[\"-heroic\",\"-tweaks\",\"firefox\",\"htop\"]' ]]"; then
  pass "lib: an app ticked by default on one desktop is picked there and nowhere else, and unticking it there is kept"
else fail "lib: defaultOn: $(cat "$work/out")"; fi
# without a desktop: only the terminal apps, and only those among the defaults
if lib "[[ \$(apps_picked '$work/catalog.json' '$work/none.json' none) == htop && \$(apps_categories '$work/catalog.json' none) == Terminal && \$(apps_offered '$work/catalog.json' none) == htop && \$(printf 'htop\n' | apps_file '$work/catalog.json' none | jq -c .) == '[\"htop\"]' && \$(printf '' | apps_file '$work/catalog.json' none | jq -c .) == '[\"-htop\"]' ]]"; then
  pass "lib: without a desktop, only terminal apps are offered, and only the terminal defaults are picked"
else fail "lib: apps without a desktop: $(cat "$work/out")"; fi
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

restore=$(tool ephemeral-restore)
snaps=$ROOT/persist/.snapshots
live=$ROOT/persist/home/alice/notes.txt
mkdir -p "$snaps/1/snapshot/home/alice" "$snaps/2/snapshot/home/alice" "$snaps/3/snapshot/home/alice" "${live%/*}"
printf 'from 1\n' >"$snaps/1/snapshot/home/alice/notes.txt"
printf 'from 2\n' >"$snaps/2/snapshot/home/alice/notes.txt"
printf '<snapshot><num>2</num><date>2026-11-20 10:00:00</date></snapshot>\n' >"$snaps/2/info.xml"
printf 'now\n' >"$live"
fake gum 'cat >"$FAKE_MENU"; sed -n "${FAKE_LINE:-1}p" "$FAKE_MENU"'
FAKE_MENU=$work/menu on_tty 'y\n' bash "$restore" /home/alice/notes.txt || true
aside=$(compgen -G "$live.before-restore-*" || true)
if [[ $(<"$live") == "from 2" && -n $aside && $(<"$aside") == now ]] &&
  [[ $(wc -l <"$work/menu") == 2 ]] && grep -q '^2  ' "$work/menu" && ! grep -q '^3' "$work/menu"; then
  pass "restore: offers only the snapshots that have it, newest first, and keeps what was there aside"
else fail "restore: $(cat "$work/out")"; fi
FAKE_MENU=$work/menu FAKE_LINE=2 on_tty 'n\n' bash "$restore" /home/alice/notes.txt || true
if [[ $(<"$live") == "from 2" && $(compgen -G "$live.before-restore-*" | wc -l) == 1 ]]; then
  pass "restore: saying no changes nothing"
else fail "restore after no: $(cat "$work/out")"; fi
if ! on_tty 'y\n' bash "$restore" /etc/passwd && grep -q "isn't in /home or on /persist" "$work/out"; then
  pass "restore: refuses a path that isn't kept"
else fail "restore outside /persist: $(cat "$work/out")"; fi
rm "$fakes/gum"

# every command: --help works, an unknown option is refused before anything runs, and the ones
# with questions stop without a terminal instead of doing nothing and exiting 0
fake gum 'exit 0'
export CATALOG=$work/catalog.json
for name in ephemeral-update ephemeral-doctor ephemeral-setup ephemeral-apps ephemeral-backup ephemeral-passwd \
  ephemeral-report ephemeral-restore controld-setup smb-setup backup-setup luks-header-backup settings-from-pass ssh-pubs-from-pass; do
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
for name in ephemeral-setup ephemeral-apps ephemeral-passwd controld-setup smb-setup ephemeral-backup ephemeral-restore backup-setup; do
  args=()
  # an empty /persist, without the passphrase the test above left
  root=$ROOT
  [[ $name == backup-setup ]] && root=$work/no-backup-yet
  [[ $name == ephemeral-backup ]] && args=("$work/stick")
  [[ $name == ephemeral-restore ]] && args=(/home/alice/notes.txt)
  code=0
  FAKE_FSTYPE=ext4 FAKE_SOURCE=/dev/sdb1 ROOT=$root bash "$(tool "$name")" "${args[@]}" >"$work/out" 2>&1 </dev/null || code=$?
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
