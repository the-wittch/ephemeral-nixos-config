#!/usr/bin/env bash
# Sets code=true in $GITHUB_OUTPUT unless only docs changed since the base: the PR's base, or
# the commit before a push to main. Anything it can't compare against counts as code.

set -euo pipefail

base=
case ${GITHUB_EVENT_NAME:-} in
  pull_request) base=${PR_BASE:-} ;;
  push) base=${PUSH_BEFORE:-} ;;
esac

# whether the change to Markdown file $1 touches a ```nix block, which checks.docs-examples
# evaluates: the lines it changed, by their numbers after the change, against the blocks then
touches_nix_example() {
  local changed
  changed=$(git diff -U0 "$base" HEAD -- "$1" | awk '/^@@/ {
    split($3, n, ","); start = substr(n[1], 2); len = (n[2] == "" ? 1 : n[2])
    # a deletion has no lines after the change; the line it was above is where it was
    if (len == 0) { len = 1; start++ }
    for (i = start; i < start + len; i++) print i
  }')
  [[ -n $changed ]] || return 1
  git show "HEAD:$1" 2>/dev/null | awk -v changed="$changed" '
    BEGIN { split(changed, c, "\n"); for (i in c) hit[c[i]] = 1 }
    /^```nix$/ { inside = 1 }
    inside && hit[NR] { found = 1 }
    /^```$/ { inside = 0 }
    END { exit !found }'
}

code=true
if [[ -n $base ]] && git cat-file -e "$base^{commit}" 2>/dev/null; then
  files=$(git diff --name-only "$base" HEAD)
  if ! grep -qvE '^docs/|\.md$|^LICENSE$|^\.github/(ISSUE_TEMPLATE/|pull_request_template\.md$)' <<<"$files"; then
    code=false
    while read -r file; do
      if [[ $file == docs/*.md ]] && touches_nix_example "$file"; then
        code=true
      fi
    done <<<"$files"
  fi
fi

echo "code=$code" >>"${GITHUB_OUTPUT:-/dev/stdout}"
echo "anything besides docs changed: $code"
