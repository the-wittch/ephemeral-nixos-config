#!/usr/bin/env bash
# settings.from-pass.json from Proton Pass.
# merge: defaults // settings.json // settings.from-pass.json
# usePassSettings = false ignores the file.
#
#   settings-from-pass
#   PASS_SETTINGS_VAULT=Personal PASS_SETTINGS_ITEM=nixos-settings settings-from-pass

set -euo pipefail

REPO_ROOT=${FLAKE_DIR:-/persist/etc/nixos}
[[ -f $REPO_ROOT/flake.nix ]] || die "no flake at $REPO_ROOT (set FLAKE_DIR)"

OUT="$REPO_ROOT/settings.from-pass.json"
VAULT=${PASS_SETTINGS_VAULT:-Personal}
ITEM=${PASS_SETTINGS_ITEM:-nixos-settings}

# bools in Pass are the strings true/false
STRING_KEYS=(
  hostname
  username
  diskDevice
  swapSize
  timeZone
  desktop
)
BOOL_KEYS=(
  useFlakePassCli
)

need() {
  command -v "$1" >/dev/null || {
    echo "need $1 on PATH (rebuild so pass-cli is installed, then: pass-cli login)" >&2
    exit 1
  }
}

need pass-cli

write_root_file() {
  local dest=$1
  local content=$2
  local tmp
  tmp=$(mktemp)
  printf '%s\n' "$content" >"$tmp"
  sudo mkdir -p /persist/etc
  sudo install -m 600 "$tmp" "$dest"
  rm -f "$tmp"
}

# empty if the field isn't there
get_field() {
  local key=$1
  local uri="pass://${VAULT}/${ITEM}/${key}"
  local out
  if ! out=$(pass-cli item view "$uri" 2>/dev/null); then
    return 0
  fi
  # item view prints the value with a trailing newline
  printf '%s' "$out" | tr -d '\r' | sed -z 's/\n$//'
}

echo "Reading Pass item: vault=${VAULT} item=${ITEM}"
echo "Writing: $OUT"
echo

obj={}
found=0

for key in "${STRING_KEYS[@]}"; do
  val=$(get_field "$key" || true)
  if [[ -n ${val:-} ]]; then
    obj=$(jq --arg k "$key" --arg v "$val" '.[$k] = $v' <<<"$obj")
    echo "  + $key"
    found=$((found + 1))
  else
    echo "  · $key (missing, using settings.json / defaults)"
  fi
done

for key in "${BOOL_KEYS[@]}"; do
  val=$(get_field "$key" || true)
  val=$(printf '%s' "${val:-}" | tr '[:upper:]' '[:lower:]')
  case $val in
    true | false)
      obj=$(jq --arg k "$key" --argjson v "$val" '.[$k] = $v' <<<"$obj")
      echo "  + $key"
      found=$((found + 1))
      ;;
    "")
      echo "  · $key (missing, using settings.json / defaults)"
      ;;
    *)
      echo "  ! $key ignored (want true/false, got: $val)" >&2
      ;;
  esac
done

repo=$(get_field chezmoiRepo || true)
rev=$(get_field chezmoiRev || true)
if [[ -n ${repo:-} || -n ${rev:-} ]]; then
  if [[ -z ${repo:-} || -z ${rev:-} ]]; then
    echo "  ! chezmoi needs both chezmoiRepo and chezmoiRev" >&2
    exit 1
  fi
  if [[ ! $rev =~ ^[0-9a-fA-F]{40}$ ]]; then
    echo "  ! chezmoiRev must be the full 40-character commit hash" >&2
    exit 1
  fi
  case $repo in
    https://* | ssh://* | git@*) ;;
    *)
      echo "  ! chezmoiRepo must start with https://, ssh://, or git@" >&2
      exit 1
      ;;
  esac
  write_root_file /persist/etc/chezmoi-repo "$repo $rev"
  echo "  + chezmoi-repo"
fi

resolver=$(get_field controldResolver || true)
if [[ -n ${resolver:-} ]]; then
  if [[ ! $resolver =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "  ! controldResolver has unexpected characters" >&2
    exit 1
  fi
  write_root_file /persist/etc/controld-resolver "$resolver"
  obj=$(jq '.useControlD = true' <<<"$obj")
  echo "  + controld-resolver"
  found=$((found + 1))
fi

# owner-only from the moment it exists
(
  umask 077
  printf '%s\n' "$obj" >"$OUT.tmp"
)
mv -f "$OUT.tmp" "$OUT"
echo
echo "Wrote $found field(s) → $OUT"
echo "Next: sudo nixos-rebuild switch --flake path:.#nixos"
