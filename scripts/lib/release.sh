# shellcheck shell=bash

# shellcheck disable=SC2329 # not every command calls it
release_repo() { echo the-wittch/ephemeral-nixos-config; }

# the vX.Y.Z of this repo a flake.nix pins, or nothing when it pins something else
# shellcheck disable=SC2329 # not every command calls it
pinned_release() {
  sed -nE "s#.*\"github:$(release_repo)/(v[0-9]+\.[0-9]+\.[0-9]+)\".*#\1#p" "$1/flake.nix" | head -n 1
}

# the newest release, or nothing when offline or when GitHub answers with anything but a vX.Y.Z
# shellcheck disable=SC2329 # not every command calls it
latest_release() {
  local tag
  tag=$(curl -fsS --max-time 5 "https://api.github.com/repos/$(release_repo)/releases/latest" 2>/dev/null |
    jq -r '.tag_name // empty' 2>/dev/null) || tag=
  [[ $tag =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] && printf '%s\n' "$tag"
  return 0
}

# whether release $1 comes after $2; both have to be vX.Y.Z
# shellcheck disable=SC2329 # not every command calls it
is_newer() {
  [[ $1 =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ && $2 =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ && $1 != "$2" ]] &&
    [[ $(printf '%s\n' "$1" "$2" | sort -V | tail -n 1) == "$1" ]]
}
