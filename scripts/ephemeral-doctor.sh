#!/usr/bin/env bash

set -euo pipefail

flake=$(flake_dir)
header_marker=/persist/etc/ephemeral/luks-header-backup

usage() {
  cat <<'USAGE'
ephemeral-doctor [kept | lost | audit | --fix-root-reset]

With nothing: check this machine, and say how to fix whatever isn't right.

  kept              the folders and files kept across reboots
  lost              files written on / since this boot, which the next reboot removes
  audit             service state in /var/lib that isn't kept, and kept folders nothing uses
  --fix-root-reset  make / reset at every boot again, when the check says it doesn't
USAGE
}

failures=0
ok() { printf '✓ %s\n' "$1"; }
warn() {
  printf '! %s\n' "$1"
  [[ -z ${2:-} ]] || printf '    %s\n' "$2"
}
bad() {
  printf '✗ %s\n' "$1"
  [[ -z ${2:-} ]] || printf '    %s\n' "$2"
  failures=$((failures + 1))
}

percent_used() { df --output=pcent "$1" | tail -n 1 | tr -dc 0-9; }

boot_time() { awk '/^btime/ { print $2 }' /proc/stat; }

# the attributes and a list header, but not one entry; or no variable at all
dbx_empty() {
  local dbx=${EPHEMERAL_ROOT:-}/sys/firmware/efi/efivars/dbx-d719b2cb-3d3a-4596-a3bc-dad00e67656f
  [[ ! -e $dbx ]] || (($(stat -c %s "$dbx") < 76))
}

fix_root_reset() {
  require_tty
  [[ $EUID -eq 0 ]] || exec sudo "$0" --fix-root-reset
  local top=/mnt/ephemeral-btrfs
  mkdir -p "$top"
  mount -o subvolid=5 /dev/mapper/cryptroot "$top"
  trap 'umount "$top"; rmdir "$top"' EXIT
  if [[ -e $top/root-blank ]]; then
    echo "root-blank is there, so that isn't what stopped the reset. journalctl -b -u rollback says what did."
    exit 1
  fi
  ask "Make an empty root-blank, so / is reset again from the next boot?" || exit 0
  btrfs subvolume create "$top/blank"
  btrfs subvolume snapshot -r "$top/blank" "$top/root-blank"
  btrfs subvolume delete "$top/blank"
  echo "Done. / is reset at the next boot; reboot when it suits you."
}

# EPHEMERAL_ROOT is for the tests
audit() {
  local root=${EPHEMERAL_ROOT:-} list d p unit dyn rest dir dirs entry found=0
  list=$root/etc/ephemeral/kept
  [[ -r $list ]] || die "$list is missing; it comes with v4.1.0 and later"
  [[ $EUID -eq 0 ]] || echo "Run it with sudo to see into folders only root can read." >&2
  local -a kept others=()
  local -A seen=()
  mapfile -t kept <"$list"

  is_kept() {
    local k
    for k in "${kept[@]}"; do
      [[ $1 == "${k%/}" || ($k == */ && $1 == "$k"*) ]] && return 0
    done
    return 1
  }
  holds_kept() {
    local k
    for k in "${kept[@]}"; do [[ $k == "$1"/* ]] && return 0; done
    return 1
  }
  has_content() {
    if [[ -d $1 ]]; then [[ -n $(find "$1" -mindepth 1 -not -type d -print -quit 2>/dev/null) ]]; else [[ -s $1 ]]; fi
  }
  size() {
    local s
    s=$(du -sh "$1" 2>/dev/null | cut -f1) || true
    echo "${s:-?}"
  }

  echo "This only looks at /var/lib and the folders services tell systemd about."
  echo "Everything else that the next reboot removes: ephemeral-doctor lost"
  echo

  # "<unit> <DynamicUser> <state dirs...>" per service
  dirs=$(systemctl list-units --type=service --all --no-legend --plain 2>/dev/null | awk '{ print $1 }' |
    xargs -r systemctl show -p Id,DynamicUser,StateDirectory -- 2>/dev/null |
    awk -F= '/^Id=/ { id = $2 } /^DynamicUser=/ { dyn = $2 } /^StateDirectory=/ { sd = $2 }
      /^$/ { if (sd != "") print id, dyn, sd; id = dyn = sd = "" }
      END { if (sd != "") print id, dyn, sd }') || dirs=
  while read -r unit dyn rest; do
    [[ -n ${unit:-} ]] || continue
    for dir in $rest; do
      dir=${dir%%:*}
      p=/var/lib/$dir
      [[ $dyn == yes ]] && p=/var/lib/private/$dir
      [[ -z ${seen[$p]:-} ]] || continue
      seen[$p]=1
      if ! is_kept "$p" && ! is_kept "/var/lib/$dir" && [[ -e $root$p ]] && has_content "$root$p"; then
        entry="\"$p\""
        [[ $dyn == yes ]] && entry="{ directory = \"$p\"; mode = \"0700\"; }"
        warn "$unit keeps its state in $p ($(size "$root$p")), which isn't kept, so it starts over at every boot" \
          "to keep it, add $entry to environment.persistence.\"/persist\".directories, as in docs/persistence.md"
        found=1
      fi
    done
  done <<<"$dirs"
  ((found)) || ok "every service's declared state is kept"

  for d in "$root"/var/lib/* "$root"/var/lib/private/*; do
    p=${d#"$root"}
    [[ -e $d && ! -L $d && $p != /var/lib/private ]] || continue
    [[ -z ${seen[$p]:-} ]] || continue
    is_kept "$p" || holds_kept "$p" || ! has_content "$d" || others+=("$p ($(size "$d"))")
  done
  if ((${#others[@]})); then
    echo "· also in /var/lib and gone at the next boot, which is usually fine:"
    printf '    %s\n' "${others[@]}"
  fi

  found=0
  for d in "$root"/persist/var/lib/* "$root"/persist/var/lib/private/*; do
    p=${d#"$root"/persist}
    [[ -e $d && $p != /var/lib/private ]] || continue
    is_kept "$p" || holds_kept "$p" && continue
    warn "/persist$p ($(size "$d")) is still on disk, but this system doesn't keep $p any more, so nothing sees it" \
      "if you won't turn it back on: sudo rm -rf /persist$p"
    found=1
  done
  ((found)) || ok "everything in /persist/var/lib is in use"
}

case ${1:-} in
  -h | --help)
    usage
    exit 0
    ;;
  audit)
    audit
    exit 0
    ;;
  kept)
    cat /etc/ephemeral/kept
    exit 0
    ;;
  lost)
    [[ $EUID -eq 0 ]] || echo "Run it with sudo to see files only root can read." >&2
    # kept files are mounted onto / one by one, so -xdev doesn't leave them out by itself
    find / -xdev -type f -newermt "@$(boot_time)" -not -path '/tmp/*' 2>/dev/null |
      awk -v list="$(cat /etc/ephemeral/kept 2>/dev/null)" 'BEGIN { n = split(list, kept, "\n") }
        { for (i = 1; i <= n; i++) if ($0 == kept[i] || (kept[i] ~ /\/$/ && index($0, kept[i]) == 1)) next; print }' || true
    exit 0
    ;;
  --fix-root-reset)
    fix_root_reset
    exit 0
    ;;
  "") ;;
  *) usage_error ;;
esac

# / is reset in the initrd; the check after boot says whether it happened
if systemctl cat root-reset-check.service >/dev/null 2>&1; then
  case $(systemctl is-active root-reset-check.service 2>/dev/null || true) in
    active) ok "/ was wiped at this boot" ;;
    failed) bad "/ wasn't wiped at this boot, so files outside the kept ones stay" "sudo ephemeral-doctor --fix-root-reset" ;;
    *) warn "/ hasn't been reset since this system was installed; it starts at the next boot" ;;
  esac
fi

if findmnt /persist >/dev/null 2>&1; then
  used=$(percent_used /persist)
  if ((used >= 90)); then
    bad "/persist is $used% full" "ephemeral-doctor kept, and sudo du -sh /persist/var/lib/* to see what's using it"
  else
    ok "/persist is mounted, $used% used"
  fi
else
  bad "/persist isn't mounted, so nothing is being kept" "journalctl -b -u persist.mount"
fi

used=$(percent_used /nix)
generations=$(find /nix/var/nix/profiles -maxdepth 1 -name 'system-*-link' 2>/dev/null | wc -l || true)
if ((used >= 90)); then
  warn "/nix is $used% full, holding $generations systems" "sudo nix-collect-garbage --delete-older-than 14d"
else
  ok "/nix is $used% used; it holds $generations systems, and the boot menu offers the newest five"
fi

failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{ print $1 }' | paste -sd ' ')
user_failed=$(systemctl --user --failed --no-legend --plain 2>/dev/null | awk '{ print $1 }' | paste -sd ' ')
if [[ -n $failed$user_failed ]]; then
  for unit in $failed; do bad "$unit failed" "journalctl -b -u $unit"; done
  for unit in $user_failed; do bad "$unit failed (yours)" "journalctl --user -b -u $unit"; done
else
  ok "no service has failed"
fi

if systemctl cat snapper-timeline.timer >/dev/null 2>&1; then
  last=$(systemctl show snapper-timeline.service -p ExecMainExitTimestamp --value)
  if [[ -z $last ]]; then
    warn "no snapshot of /persist yet this boot; the first comes within the hour"
  else
    age=$((($(date +%s) - $(date -d "$last" +%s)) / 60))
    if ((age > 120)); then
      bad "the last snapshot of /persist was taken $age minutes ago; they're hourly" "systemctl status snapper-timeline.service"
    else
      ok "the last snapshot of /persist is $age minutes old"
    fi
  fi
fi

if [[ -r $flake/flake.nix ]]; then
  pinned=$(pinned_release "$flake")
  latest=$(latest_release)
  if [[ -z $pinned ]]; then
    ok "the config pins its own release of $(release_repo)"
  elif [[ -z $latest ]]; then
    ok "the config is on $pinned (offline, so not compared with the newest)"
  elif is_newer "$latest" "$pinned"; then
    warn "the config is on $pinned; $latest is out" "ephemeral-update"
  else
    ok "the config is on $pinned, the newest release"
  fi
  secrets=$(secret_files "$flake")
  if [[ -n $secrets ]]; then
    bad "files that look like secrets are in $flake, and a rebuild copies them where any user can read them" \
      "move them out: $(printf '%s' "$secrets" | paste -sd ' ')"
  else
    ok "no secret files in $flake"
  fi
else
  bad "can't read $flake" "sudo chmod 755 $flake"
fi

if [[ -s $header_marker ]]; then
  ok "LUKS header backed up $(cut -d' ' -f1 "$header_marker")"
else
  warn "no LUKS header backup made on this machine; without one, a damaged header loses the whole disk" \
    "luks-header-backup /run/media/$USER/<stick>/luks-header.img"
fi

if [[ -e ${EPHEMERAL_ROOT:-}/etc/ephemeral/secure-boot ]]; then
  if secure_boot_on; then
    # only this machine's key signs Limine, so a boot with it on means that key is trusted
    ok "Secure Boot is on, with this machine's keys"
    if [[ -z $(efi_flag SecureBoot) ]]; then
      warn "the firmware hides its Secure Boot variables from Linux at this boot, so the revocation list (dbx) can't be checked" \
        "nothing to fix for Secure Boot itself; bootctl says \"unsupported\" for the same reason (docs/troubleshooting.md)"
    elif dbx_empty; then
      warn "the firmware has no list of revoked bootloaders (dbx), so ones Microsoft has revoked still start" \
        "fwupdmgr refresh && fwupdmgr update"
    fi
  elif [[ $(efi_flag SetupMode) == 1 ]]; then
    warn "the firmware is in Setup Mode, waiting for this machine's keys" \
      "ephemeral-update puts them in; then turn Secure Boot on in the firmware (docs/security.md)"
  elif [[ -z $(efi_flag SetupMode) ]]; then
    warn "the firmware doesn't report Secure Boot at all, so the keys can't be enrolled" \
      "look in its Secure Boot settings for Secure Boot being turned off or hidden altogether (docs/troubleshooting.md)"
  else
    warn "secureBoot is on in settings.json, but Secure Boot is off in the firmware" \
      "if the keys are enrolled, turn it on in the firmware; if not, see docs/security.md"
  fi
fi

if [[ -e ${EPHEMERAL_ROOT:-}/etc/ephemeral/tpm-unlock ]]; then
  if ! secure_boot_on; then
    # the TPM key is bound to Secure Boot being on, so it can't match
    bad "the disk is set to unlock with the TPM, but Secure Boot is off, so the PIN can't unlock it and every boot asks for the passphrase after it" \
      "turn Secure Boot on in the firmware (docs/security.md)"
  elif [[ $EUID -ne 0 ]]; then
    ok "the disk unlocks with the TPM and a PIN (sudo ephemeral-doctor checks the disk's TPM slot)"
  # read whole first: grep -q stopping early would fail luksDump, which pipefail counts
  elif grep -q systemd-tpm2 <<<"$(sudo cryptsetup luksDump "$(luks_device)" 2>/dev/null)"; then
    ok "the disk unlocks with the TPM and a PIN, with the passphrase as the fallback"
  else
    bad "the disk is set to unlock with the TPM, but it has no TPM slot, so every boot asks for the passphrase" \
      "ephemeral-setup, and pick the TPM PIN"
  fi
fi

if [[ -e ${EPHEMERAL_ROOT:-}/etc/ephemeral/server ]]; then
  # shellcheck disable=SC2154 # initrd_ssh_boot_key comes from the prelude
  boot_key=${EPHEMERAL_ROOT:-}$initrd_ssh_boot_key
  start=
  if [[ ! -x $(dirname "$boot_key") ]]; then
    ok "this server can be unlocked over SSH at boot (sudo ephemeral-doctor checks its key)"
  elif [[ ! -s $boot_key ]]; then
    bad "there's no key for unlocking this server over SSH at boot, so it only unlocks at the keyboard" "ephemeral-update"
  else
    IFS= read -r -n 10 start <"$boot_key" || true
    if [[ $start != -----BEGIN ]]; then
      ok "this server can be unlocked over SSH at boot, with its key sealed to the TPM"
    elif secure_boot_on && tpm_present; then
      warn "the key for unlocking this server over SSH at boot isn't sealed to the TPM, so anyone with the disk can read it from the boot partition" \
        "ephemeral-update"
    else
      ok "this server can be unlocked over SSH at boot (its key isn't sealed: that needs Secure Boot and a TPM)"
    fi
  fi
fi

# backups.nix writes borgmatic's config only when backup.json has a repository
if [[ -e ${EPHEMERAL_ROOT:-}/etc/borgmatic/config.yaml ]]; then
  # shellcheck disable=SC2154 # backup_dir comes from the prelude
  borg_dir=${EPHEMERAL_ROOT:-}$backup_dir
  if [[ ! -x $borg_dir ]]; then
    ok "scheduled backups are on (sudo ephemeral-doctor checks their passphrase and key)"
  elif [[ ! -s $borg_dir/passphrase || ! -s $borg_dir/ssh_key ]]; then
    bad "scheduled backups are on, but their passphrase or SSH key is missing, so they can't run" "backup-setup"
  elif systemctl is-failed --quiet borgmatic.service 2>/dev/null; then
    warn "the last scheduled backup failed" "journalctl -u borgmatic"
  else
    ok "scheduled backups are on"
  fi
fi

# only reads the list fwupd-refresh.timer downloads; installing stays a choice, since a firmware
# update must not be cut off, and can change what the TPM PIN is bound to
if command -v fwupdmgr >/dev/null; then
  status=0
  updates=$(timeout 30 fwupdmgr get-updates --json --no-unreported-check --no-metadata-check 2>/dev/null) || status=$?
  if ((status == 2)); then
    ok "no firmware updates waiting"
  elif ((status == 0)); then
    pending=$(jq -r '.Devices[]? | select((.Releases // []) != []) | "\(.Name) \(.Version) → \(.Releases[0].Version)"' <<<"$updates" 2>/dev/null || true)
    if [[ -n $pending ]]; then
      warn "firmware updates are waiting:"
      printf '%s\n' "$pending" | sed 's/^/      /'
      printf '    %s\n' "fwupdmgr update, with the charger in and your work saved; most install while the machine restarts"
      if [[ -e ${EPHEMERAL_ROOT:-}/etc/ephemeral/tpm-unlock ]] &&
        jq -e '[.Devices[]? | select(.Plugin == "uefi_capsule" or .Plugin == "uefi_dbx")] != []' <<<"$updates" >/dev/null 2>&1; then
        printf '    %s\n' "after the system firmware or dbx update, the boot may ask for the passphrase instead of the PIN; then run ephemeral-setup to enroll the PIN again"
      fi
    else
      ok "no firmware updates waiting"
    fi
  fi
fi

if systemctl is-active --quiet opensnitchd.service 2>/dev/null; then
  ok "OpenSnitch is on: a program has to be allowed before it connects out"
fi

exit $((failures > 0))
