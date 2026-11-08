#!/usr/bin/env bash
# Sets code=true in $GITHUB_OUTPUT unless only docs changed since the base: the PR's base,
# the commit before a push to main, or the previous release for a tag. Anything it can't
# compare against counts as code.

set -euo pipefail

base=
case ${GITHUB_EVENT_NAME:-} in
  pull_request) base=${PR_BASE:-} ;;
  push)
    if [[ ${GITHUB_REF:-} == refs/tags/* ]]; then
      base=$(git describe --tags --abbrev=0 --match 'v*.*.*' HEAD^ 2>/dev/null || true)
    else
      base=${PUSH_BEFORE:-}
    fi
    ;;
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
