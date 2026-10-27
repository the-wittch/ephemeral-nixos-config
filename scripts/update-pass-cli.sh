#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
update-pass-cli [--check | --check-only] [x.y.z]
Bump or verify modules/packages/pass-cli.json against GitHub releases.
Run from a checkout of the config repo, or set FLAKE_DIR.
USAGE
}

REPO_ROOT=${FLAKE_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || true)}
PIN="$REPO_ROOT/modules/packages/pass-cli.json"
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
      usage
      exit 0
      ;;
    *)
      version_arg=$arg
      ;;
  esac
done

[[ -f $PIN ]] || die "no modules/packages/pass-cli.json under ${REPO_ROOT:-the current directory} (cd into the config repo or set FLAKE_DIR)"

pinned_ver=$(jq -r .version "$PIN")
pinned_hash=$(jq -r .hash "$PIN")

if [[ $mode == check ]]; then
  target_ver=$pinned_ver
  echo "Checking $ASSET @ $target_ver …"
else
  target_ver=${version_arg:-$(curl -fsSL "$API/latest" | jq -r '.tag_name | ltrimstr("v")')}
  echo "Target version: $target_ver (pinned was $pinned_ver)"
fi

[[ $target_ver =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "refusing version that is not x.y.z: $target_ver"

hex=$(curl -fsSL "https://github.com/protonpass/pass-cli/releases/download/${target_ver}/${ASSET}.sha256" | awk '{print $1}')
[[ $hex =~ ^[0-9a-f]{64}$ ]] || die "bad upstream sha256 for $target_ver: $hex"
sri=$(nix hash convert --hash-algo sha256 --to sri "$hex")
echo "Upstream: $sri"

if [[ $target_ver == "$pinned_ver" && $sri == "$pinned_hash" ]]; then
  echo "ok: modules/packages/pass-cli.json already matches upstream."
  exit 0
fi

if [[ $check_only -eq 1 ]]; then
  echo "mismatch: pinned hash/version differ from upstream." >&2
  echo "  pinned:   $pinned_ver $pinned_hash" >&2
  echo "  upstream: $target_ver $sri" >&2
  exit 1
fi

# shellcheck disable=SC2016 # $v and $h are jq's
jq_edit "$PIN" --arg v "$target_ver" --arg h "$sri" '.version = $v | .hash = $h'
echo "Updated $PIN → $target_ver"
echo "Rebuild when ready: sudo nixos-rebuild switch --flake path:.#nixos"
