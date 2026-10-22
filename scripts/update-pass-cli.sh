#!/usr/bin/env bash
# Bump or verify packages/pass-cli.nix against GitHub releases.
#
#   update-pass-cli              # latest release
#   update-pass-cli 2.4.2        # specific version
#   update-pass-cli --check      # verify pinned version hash; rewrite if wrong
#   update-pass-cli --check-only # verify only (exit 1 if mismatch, no write)

set -euo pipefail

if [[ -n ${FLAKE_DIR:-} ]]; then
  REPO_ROOT=$FLAKE_DIR
elif [[ -f /persist/etc/nixos/packages/pass-cli.nix ]]; then
  REPO_ROOT=/persist/etc/nixos
else
  REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd)
fi
PKG="$REPO_ROOT/packages/pass-cli.nix"
ASSET=pass-cli-linux-x86_64
API=https://api.github.com/repos/protonpass/pass-cli/releases

mode=bump
version_arg=
check_only=0

for arg in "$@"; do
  case $arg in
    --check) mode=check ;;
    --check-only)
      mode=check
      check_only=1
      ;;
    -h | --help)
      sed -n '2,7p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      version_arg=$arg
      ;;
  esac
done

[[ -f $PKG ]] || {
  echo "missing $PKG" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null || {
    echo "need $1 on PATH" >&2
    exit 1
  }
}

need curl
need python3
need sed
need grep

hex_to_sri() {
  local hex=$1
  if command -v nix >/dev/null; then
    nix hash to-sri --type sha256 "$hex"
  else
    python3 - "$hex" <<'PY'
import base64, binascii, sys
print("sha256-" + base64.b64encode(binascii.unhexlify(sys.argv[1].strip())).decode())
PY
  fi
}

read_pinned_version() {
  grep -E '^\s*version\s*=' "$PKG" | head -1 | sed -E 's/.*"([^"]+)".*/\1/'
}

read_pinned_hash() {
  grep -E '^\s*hash\s*=' "$PKG" | head -1 | sed -E 's/.*"([^"]+)".*/\1/'
}

latest_version() {
  curl -fsSL "$API/latest" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"].lstrip("v"))'
}

fetch_hex() {
  local ver=$1
  local url="https://github.com/protonpass/pass-cli/releases/download/${ver}/${ASSET}.sha256"
  # file is: "<hex>  pass-cli-linux-x86_64"
  curl -fsSL "$url" | awk '{print $1}'
}

write_pkg() {
  local ver=$1
  local sri=$2
  local tmp
  tmp=$(mktemp)
  sed -E \
    -e "s/^(  version = \")[^\"]+(\";)/\1${ver}\2/" \
    -e "s|^(    hash = \")[^\"]+(\";)|\1${sri}\2|" \
    "$PKG" >"$tmp"
  # sanity: both lines changed
  grep -q "version = \"${ver}\"" "$tmp" || {
    echo "failed to set version" >&2
    exit 1
  }
  grep -q "hash = \"${sri}\"" "$tmp" || {
    echo "failed to set hash" >&2
    exit 1
  }
  mv "$tmp" "$PKG"
}

pinned_ver=$(read_pinned_version)
pinned_hash=$(read_pinned_hash)

if [[ $mode == check ]]; then
  target_ver=$pinned_ver
  echo "Checking $ASSET @ $target_ver …"
else
  target_ver=${version_arg:-$(latest_version)}
  echo "Target version: $target_ver (pinned was $pinned_ver)"
fi

# sed writes this straight into the nix string
if [[ ! $target_ver =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "refusing version that is not x.y.z" >&2
  exit 1
fi

hex=$(fetch_hex "$target_ver")
[[ $hex =~ ^[0-9a-f]{64}$ ]] || {
  echo "bad upstream sha256 for $target_ver: $hex" >&2
  exit 1
}
sri=$(hex_to_sri "$hex")
echo "Upstream: $sri"

if [[ $target_ver == "$pinned_ver" && $sri == "$pinned_hash" ]]; then
  echo "ok: packages/pass-cli.nix already matches upstream."
  exit 0
fi

if [[ $mode == check && $check_only -eq 1 ]]; then
  echo "mismatch: pinned hash/version differ from upstream." >&2
  echo "  pinned:  $pinned_ver $pinned_hash" >&2
  echo "  upstream: $target_ver $sri" >&2
  exit 1
fi

write_pkg "$target_ver" "$sri"
echo "Updated $PKG → $target_ver"
echo "Rebuild when ready: sudo nixos-rebuild switch --flake path:.#nixos"
