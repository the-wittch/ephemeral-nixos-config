#!/usr/bin/env bash
# changelog-add.sh CHANGELOG.md 3.4.1 "- nixpkgs updated."
# adds the line under Changed in that version's entry, adding the entry if there isn't one yet
set -euo pipefail

file=$1
version=$2
line=$3

grep -qxF -- "$line" "$file" && exit 0

awk -v heading="## $version" -v line="$line" '
  function changed() { printf "### Changed\n\n%s\n\n", line; done = 1 }
  !done && !seen && /^## / && $0 != heading { print heading "\n"; changed(); print; next }
  $0 == heading { seen = 1; print; next }
  seen && !done && /^## / { changed(); print; next }
  seen && !done && $0 == "### Changed" { print; getline; print; print line; done = 1; next }
  { print }
  END { if (seen && !done) { print ""; changed() } }
' "$file" >"$file.new"
mv "$file.new" "$file"
