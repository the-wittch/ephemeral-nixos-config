#!/usr/bin/env bash
# .github/eval-checks.sh              evaluate every check, then build the ones without a VM
# .github/eval-checks.sh --no-build   only evaluate them
# nix flake check evaluates everything in one process and runs out of memory, so this
# does one check per process. VM tests are only evaluated; build them with nix build.
set -euo pipefail

build=1
case ${1:-} in
  --no-build) build=0 ;;
  "") ;;
  *)
    sed -n '2,3s/^# //p' "$0" >&2
    exit 2
    ;;
esac

if [[ ! -f settings.json || ! -f hardware-configuration.nix ]]; then
  echo "error: run it from the repo root, after:" >&2
  echo "  cp settings.example.json settings.json" >&2
  echo "  cp hardware-configuration.example.nix hardware-configuration.nix" >&2
  exit 1
fi

checks=path:.#checks.x86_64-linux
drvs=()
for check in $(nix eval --raw "$checks" --apply 'c: builtins.concatStringsSep " " (builtins.attrNames c)'); do
  # only NixOS tests have a driver
  # shellcheck disable=SC2016
  out=$(nix eval --raw "$checks.$check" --apply 'd: "${d.drvPath} ${if d ? driver then "vm" else "build"}"')
  echo "evaluated $check"
  [[ ${out##* } == vm ]] || drvs+=("${out%% *}^*")
done

if ((build)) && ((${#drvs[@]})); then
  echo "building ${#drvs[@]} checks without a VM"
  nix build --no-link "${drvs[@]}"
fi
