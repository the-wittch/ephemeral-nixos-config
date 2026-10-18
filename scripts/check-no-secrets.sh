#!/usr/bin/env bash
# Block commits/pushes that look like secrets.
# Used by .githooks/pre-commit and pre-push.
#
#   check-no-secrets           # scan tracked files in the working tree
#   check-no-secrets --staged  # staged files only

set -euo pipefail

mode=tree

while [[ $# -gt 0 ]]; do
  case $1 in
    --staged) mode=staged ;;
    -h | --help)
      sed -n '2,7p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
  esac
  shift
done

FORBIDDEN_PATHS=(
  '^settings\.nix$'
  '^settings\.from-pass\.nix$'
  '^hardware-configuration\.nix$'
  '^smb-shares\.nix$'
  '^secrets\.nix$'
  '(^|/)\.env$'
  '(^|/)\.env\.'
  '\.creds$'
  '(^|/)passwords/'
  '(^|/)id_rsa$'
  '(^|/)id_ed25519$'
  '\.pem$'
  '\.age$'
)

CONTENT_PATTERNS=(
  'password[[:space:]]*=[[:space:]]*[^[:space:]#'\'']{8,}'
  'BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY'
  'hashedPassword[[:space:]]*=[[:space:]]*["'\'']\$[166]\$'
  'ghp_[A-Za-z0-9]{20,}'
  'github_pat_[A-Za-z0-9_]{20,}'
  'sk-[A-Za-z0-9]{20,}'
  '[0-9a-z]{8,}\.dns\.controld\.com'
)

# The scanner file contains the patterns themselves.
# customize/default.nix and *.example.nix are tracked starters.
skip_file() {
  case $1 in
    scripts/check-no-secrets.sh | .githooks/*) return 0 ;;
    customize/default.nix | customize/*.example.nix) return 0 ;;
    *) return 1 ;;
  esac
}

# User files under customize/ must not be committed.
is_forbidden_customize() {
  case $1 in
    customize/default.nix | customize/*.example.nix) return 1 ;;
    customize/*) return 0 ;;
    *) return 1 ;;
  esac
}

fail=0

is_forbidden_path() {
  local p=$1 re
  for re in "${FORBIDDEN_PATHS[@]}"; do
    [[ $p =~ $re ]] && return 0
  done
  return 1
}

list_files() {
  if [[ $mode == staged ]]; then
    git diff --cached --name-only --diff-filter=ACMR
  else
    git ls-files
  fi
}

mapfile -t files < <(list_files)

for p in "${files[@]}"; do
  [[ -z $p ]] && continue
  if is_forbidden_path "$p" || is_forbidden_customize "$p"; then
    echo "blocked path: $p" >&2
    fail=1
  fi
done

for p in "${files[@]}"; do
  [[ -z $p || ! -f $p ]] && continue
  if skip_file "$p"; then
    continue
  fi
  for pat in "${CONTENT_PATTERNS[@]}"; do
    if grep -nIE "$pat" -- "$p" >/dev/null 2>&1; then
      echo "blocked content in $p matching /$pat/:" >&2
      grep -nIE "$pat" -- "$p" >&2 || true
      fail=1
    fi
  done
done

if [[ $fail -ne 0 ]]; then
  echo >&2
  echo "Secret check failed. Fix the files, or override with:" >&2
  echo "  SKIP_SECRET_CHECK=1 git push" >&2
  exit 1
fi

echo "Secret check OK."
