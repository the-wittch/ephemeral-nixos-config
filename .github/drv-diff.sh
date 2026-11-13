#!/usr/bin/env bash
# .github/drv-diff.sh save <file>      record every host's system derivation
# .github/drv-diff.sh compare <file>   after a change, show which hosts differ and how
# A change that only moves code around should leave every host the same.
set -euo pipefail

if ! command -v jq >/dev/null || ! command -v nix-diff >/dev/null; then
  exec nix shell nixpkgs#jq nixpkgs#nix-diff -c "$0" "$@"
fi

current() {
  nix eval --json path:.#legacyPackages.x86_64-linux.systemDrvs
}

case ${1:-} in
  save)
    file=${2:?usage: drv-diff.sh save <file>}
    current >"$file"
    echo "saved $(jq length "$file") hosts to $file"
    ;;
  compare)
    file=${2:?usage: drv-diff.sh compare <file>}
    now=$(current)
    changed=0
    while IFS=$'\t' read -r host before after; do
      if [[ $before == "$after" ]]; then
        echo "same     $host"
        continue
      fi
      changed=1
      echo "changed  $host"
      if [[ $before == null || $after == null ]]; then
        echo "  only evaluates on one side" >&2
      else
        nix-diff "$before" "$after" | sed 's/^/  /'
      fi
    done < <(jq -rn --slurpfile a "$file" --argjson b "$now" '
      ($a[0] | keys) + ($b | keys) | unique[] as $h
      | [$h, ($a[0][$h] // null | tostring), ($b[$h] // null | tostring)] | @tsv')
    exit "$changed"
    ;;
  *)
    echo "usage: drv-diff.sh save|compare <file>" >&2
    exit 2
    ;;
esac
