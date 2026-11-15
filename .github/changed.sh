#!/usr/bin/env bash
# Sets code=true in $GITHUB_OUTPUT unless only docs changed since the base: the PR's base, or
# the commit before a push to main. Anything it can't compare against counts as code.

set -euo pipefail

base=
case ${GITHUB_EVENT_NAME:-} in
  pull_request) base=${PR_BASE:-} ;;
  push) base=${PUSH_BEFORE:-} ;;
esac

code=true
if [[ -n $base ]] && git cat-file -e "$base^{commit}" 2>/dev/null; then
  files=$(git diff --name-only "$base" HEAD)
  if ! grep -qvE '^docs/|\.md$|^LICENSE$|^\.github/(ISSUE_TEMPLATE/|pull_request_template\.md$)' <<<"$files"; then
    code=false
  fi
fi

echo "code=$code" >>"${GITHUB_OUTPUT:-/dev/stdout}"
echo "anything besides docs changed: $code"
