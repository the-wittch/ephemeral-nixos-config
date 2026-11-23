#!/usr/bin/env bash

set -euo pipefail

flake=$(flake_dir)
header_marker=/persist/etc/ephemeral/luks-header-backup

usage() {
  cat <<'USAGE'
ephemeral-doctor [persistence | kept | lost | audit | --fix-root-reset]

With nothing: check this machine, and say how to fix whatever isn't right.

  persistence       what survives a reboot and what's backed up; --help for more
  kept              the folders and files kept across reboots
  lost              files written on / since this boot, which the next reboot removes
  audit             the same as persistence --audit
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

# The service state the engine can't see from mounts: what services tell systemd they keep in
# /var/lib, and what's left on /persist that nothing keeps. Prints findings as a JSON array.
# EPHEMERAL_ROOT is for the tests.
service_findings() {
  local root=${EPHEMERAL_ROOT:-} p unit dyn rest dir dirs entry owner group mode d
  local -a kept
  local -A seen=()
  mapfile -t kept < <(jq -r '.entries[] | if .kind == "directory" then .path + "/" else .path end' \
    "$root/etc/ephemeral/kept.json")

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
  found() {
    jq -n --arg severity "$1" --arg path "$2" --arg finding "$3" --arg explanation "$4" \
      --arg evidence "$5" --arg remediation "$6" \
      '{severity: $severity, path: $path, finding: $finding, explanation: $explanation,
        evidence: $evidence, remediation: $remediation}'
  }

  {
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
          # preservation sets a kept folder's owner and mode at every boot, so they're spelled out
          # unless they're its defaults; systemd refuses DynamicUser unless /var/lib/private is 0700
          read -r owner group mode < <(stat -c '%U %G %a' "$root$p")
          entry="\"$p\""
          if [[ $dyn == yes ]]; then
            entry="{ directory = \"$p\"; mode = \"0700\"; configureParent = true; parent.mode = \"0700\"; }"
          elif [[ "$owner $group $mode" != "root root 755" ]]; then
            entry="{ directory = \"$p\"; user = \"$owner\"; group = \"$group\"; mode = \"0$mode\"; }"
          fi
          found warning "$p" "$unit keeps its state in $p ($(size "$root$p")), which isn't kept, so it starts over at every boot" \
            "the service tells systemd this is its state, and it has files in it now" \
            "StateDirectory=$dir in $unit; it's on / and not in /etc/ephemeral/kept.json" \
            "to keep it, add $entry to preservation.preserveAt.\"/persist\".directories, as in docs/persistence.md"
        fi
      done
    done <<<"$dirs"

    for d in "$root"/var/lib/* "$root"/var/lib/private/*; do
      p=${d#"$root"}
      [[ -e $d && ! -L $d && $p != /var/lib/private ]] || continue
      [[ -z ${seen[$p]:-} ]] || continue
      is_kept "$p" || holds_kept "$p" || ! has_content "$d" ||
        found informational "$p" "$p ($(size "$d")) isn't kept, so it's gone at the next boot, which is usually fine" \
          "no service says it's its state, so it's most likely made again when needed" \
          "it has files, and nothing in /etc/ephemeral/kept.json covers it" \
          "nothing to do, unless you know it matters; then keep it as in docs/persistence.md"
    done

    for d in "$root"/persist/var/lib/* "$root"/persist/var/lib/private/*; do
      p=${d#"$root"/persist}
      [[ -e $d && $p != /var/lib/private ]] || continue
      is_kept "$p" || holds_kept "$p" && continue
      found warning "/persist$p" "/persist$p ($(size "$d")) is still on disk, but this system doesn't keep $p any more, so nothing sees it" \
        "it was kept by a feature that's off now, or by an entry that's gone" \
        "nothing in /etc/ephemeral/kept.json is $p or in it" \
        "if you won't turn it back on: sudo rm -rf /persist$p"
    done
  } | jq -s .
}

persistence_usage() {
  cat <<'USAGE'
ephemeral-doctor persistence [--summary | --path PATH... | --audit] [--json]

In a terminal, with nothing: an explorer of what survives a reboot. Otherwise, or with
--summary: what the config keeps, and how this machine has it now.

  --path PATH      what happens to PATH at a reboot, and whether it's backed up
  --audit          what isn't set up as the config says, or isn't kept and may matter;
                   exits 1 when something is wrong (CRITICAL)
  --json           the same, as JSON (docs/persistence.md describes the fields)
  --children DIR   DIR and what's directly in it, as JSON; what the explorer reads

PERSISTENT  on /persist, mounted or linked from it, or on /nix, /var/log or /boot
EPHEMERAL   reset at every boot, or held in memory
MIXED       a folder that holds both kept and reset things
UNKNOWN     another disk, a network share, firmware storage, or something it can't read
UNVERIFIED  declared as kept, but not set up that way now

It only reads. Run it with sudo to see into folders only root can read.
USAGE
}

# the paths the summary and the audit look at: what's declared, the folders that hold it and
# the configured file systems, and for the audit the copies on /persist too
persist_overview_paths() {
  jq -j --argjson audit "$2" '
    ([.entries[].path] + [.filesystems[].mountPoint] + ["/"]) as $p
    | ($p | map(. as $x | ($x | split("/")) as $s | range(1; $s | length) | $s[0:.] | join("/")
        | if . == "" then "/" else . end)) as $up
    | ($p + $up + (if $audit then [.entries[] | .path as $x | "/persist" + $x] else [] end))
    | unique | .[] | . + "\u0000"' "$1/kept.json"
}

# DIR and up to 2000 of the paths directly in it, sorted; says in meta.json when there are more
persist_children() {
  local root=${EPHEMERAL_ROOT:-} dir=$1 work=$2 n
  local -a kids=()
  mapfile -d '' -t kids < <(find "$root$dir" -mindepth 1 -maxdepth 1 -print0 2>/dev/null | sort -z | head -z -n 2001)
  n=${#kids[@]}
  ((n <= 2000)) || kids=("${kids[@]:0:2000}")
  jq --argjson t "$((n > 2000))" '.truncated = ($t == 1)' "$work/meta.json" >"$work/meta.new" &&
    mv "$work/meta.new" "$work/meta.json"
  printf '%s\0' "$dir"
  ((${#kids[@]} == 0)) || printf '%s\0' "${kids[@]#"$root"}"
}

persistence() {
  local root=${EPHEMERAL_ROOT:-} json=0 audit=0 summary=0 children="" work code
  local -a paths=()
  while (($#)); do
    case $1 in
      --audit) audit=1 ;;
      --json) json=1 ;;
      --summary) summary=1 ;;
      --path)
        (($# >= 2)) || usage_error
        paths+=("$(realpath -ms -- "$2")")
        shift
        ;;
      --children)
        (($# >= 2)) || usage_error
        children=$(realpath -ms -- "$2")
        shift
        ;;
      -h | --help)
        persistence_usage
        exit 0
        ;;
      *) usage_error ;;
    esac
    shift
  done
  if ((! json && ! audit && ! summary)) && [[ -z $children && ${#paths[@]} -eq 0 && -t 0 && -t 1 ]] &&
    command -v ephemeral >/dev/null; then
    exec ephemeral persistence --engine "$0"
  fi
  [[ $EUID -eq 0 || $json -eq 1 || -n $children ]] || echo "Run it with sudo to see into folders only root can read." >&2

  work=$(persist_open)
  # shellcheck disable=SC2064 # the folder is known now
  trap "persist_close '$work'" EXIT
  jq --arg now "$(date -Is)" --arg release "$(cat "$root/etc/ephemeral/release" 2>/dev/null || echo unknown)" \
    --argjson audit "$audit" '. + {now: $now, release: $release, audit: ($audit == 1)}' \
    "$work/meta.json" >"$work/meta.new" && mv "$work/meta.new" "$work/meta.json"
  ((! audit)) || service_findings >"$work/extra.json"

  if [[ -n $children ]]; then
    persist_children "$children" "$work"
  elif ((${#paths[@]})); then
    printf '%s\0' "${paths[@]}"
  else
    persist_overview_paths "$work" "$( ((audit)) && echo true || echo false)"
  fi | persist_classify "$work"

  if ((json)) || [[ -n $children ]]; then
    persist_run json "$work"
    ((! audit)) || (($(persist_run critical "$work") == 0)) || exit 1
  elif ((audit)); then
    echo "✗ CRITICAL  ! WARNING  · INFORMATIONAL  ? UNKNOWN"
    echo
    persist_run audit "$work"
    code=$(persist_run critical "$work")
    ((code == 0)) || exit 1
  elif ((${#paths[@]})); then
    persist_run details "$work"
  else
    persist_run summary "$work"
    echo
    persist_run tree "$work"
  fi
}

case ${1:-} in
  -h | --help)
    usage
    exit 0
    ;;
  audit)
    shift
    persistence --audit "$@"
    exit 0
    ;;
  persistence)
    shift
    persistence "$@"
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

# picked.nix adds the timer on a full system with a desktop, unless flatpakUpdates is off
if [[ -e ${EPHEMERAL_ROOT:-}/etc/systemd/user/flatpak-update.timer ]]; then
  if systemctl is-failed --user --quiet flatpak-update.service 2>/dev/null; then
    warn "the last weekly Flatpak update failed" "journalctl --user -u flatpak-update"
  else
    ok "Flatpak apps are updated once a week"
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
