#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
check-no-secrets                    tracked files in the working tree
check-no-secrets --staged           the index, as it will be committed
check-no-secrets --range <revs...>  every commit in a range, e.g. HEAD or a..b
USAGE
}

mode=tree
revs=()

while [[ $# -gt 0 ]]; do
  case $1 in
    --staged) mode=staged ;;
    --range)
      mode=range
      shift
      revs=("$@")
      [[ ${#revs[@]} -gt 0 ]] || {
        echo "--range needs revisions" >&2
        exit 2
      }
      break
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 2
      ;;
  esac
  shift
done

FORBIDDEN_PATHS=(
  '^settings\.(nix|json)$'
  '^settings\.from-pass\.(nix|json)$'
  '^hardware-configuration\.nix$'
  '^smb-shares\.(nix|json)$'
  '^secrets\.nix$'
  '(^|/)\.env$'
  '(^|/)\.env\.'
  '\.creds$'
  '(^|/)passwords/'
  '(^|/)id_rsa$'
  '(^|/)id_ed25519$'
  '(^|/)id_ecdsa$'
  '\.key$'
  '\.pem$'
  '\.age$'
)

# shellcheck disable=SC2016 # literal $ in the hash pattern
CONTENT_PATTERNS=(
  'password[[:space:]]*=[[:space:]]*[^[:space:]#'\'']{8,}'
  'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY'
  'hashedPassword[[:space:]]*=[[:space:]]*["'\'']\$(y|gy|7|6|5|2[aby]?|1)\$'
  'ghp_[A-Za-z0-9]{20,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'sk-[A-Za-z0-9]{20,}'
  'AKIA[0-9A-Z]{16}'
  'AGE-SECRET-KEY-1[0-9A-Z]{50,}'
  'xox[abprs]-[A-Za-z0-9-]{10,}'
  'glpat-[A-Za-z0-9_-]{20,}'
  '[0-9a-z]{8,}\.dns\.controld\.com'
)

skip_file() {
  case $1 in
    scripts/check-no-secrets.sh | .githooks/*) return 0 ;;
    modules/local/_example.nix) return 0 ;;
    *) return 1 ;;
  esac
}

is_forbidden_path() {
  local p=$1 re
  for re in "${FORBIDDEN_PATHS[@]}"; do
    [[ $p =~ $re ]] && return 0
  done
  case $p in
    modules/local/_example.nix) return 1 ;;
    modules/local/*) return 0 ;;
  esac
  return 1
}

list_paths() {
  case $mode in
    tree) git ls-files ;;
    staged) git diff --cached --name-only --diff-filter=ACMR ;;
    range) git log --format= --name-only --diff-filter=ACMR "${revs[@]}" | sort -u ;;
  esac
}

content_lines() {
  local p
  case $mode in
    tree | staged)
      while IFS= read -r p; do
        [[ -z $p ]] && continue
        [[ $mode == staged || -f $p ]] || continue
        if [[ $mode == tree ]]; then
          grep -nI '' -- "$p" 2>/dev/null || true
        else
          git show ":$p" 2>/dev/null | grep -nI '' || true
        fi | while IFS= read -r line; do
          printf 'line %s\t%s\t%s\n' "${line%%:*}" "$p" "${line#*:}"
        done
      done < <(list_paths)
      ;;
    range)
      git log -p --no-color --unified=0 --diff-filter=ACMR --format='commit %h' "${revs[@]}" |
        awk '
          /^commit / { c = $2; next }
          /^\+\+\+ / { f = substr($0, 7); next }
          /^\+/ { printf "commit %s\t%s\t%s\n", c, f, substr($0, 2) }
        '
      ;;
  esac
}

fail=0

while IFS= read -r p; do
  [[ -z $p ]] && continue
  if is_forbidden_path "$p"; then
    echo "blocked path: $p" >&2
    fail=1
  fi
done < <(list_paths)

while IFS=$'\t' read -r where p text; do
  skip_file "$p" && continue
  for pat in "${CONTENT_PATTERNS[@]}"; do
    if [[ $text =~ $pat ]]; then
      echo "blocked content in $p ($where) matching /$pat/" >&2
      fail=1
    fi
  done
done < <(content_lines)

if [[ $fail -ne 0 ]]; then
  echo >&2
  echo "Secret check failed. Fix the files, or override with:" >&2
  echo "  SKIP_SECRET_CHECK=1 git commit ...   (or git push)" >&2
  exit 1
fi

echo "Secret check OK."
