#!/usr/bin/env bash

set -euo pipefail

case ${1:-} in
  -h | --help)
    cat <<'USAGE'
ephemeral-setup
Switch between the minimal and full profile and turn the main options on or off,
then rebuild. Run it again any time to change them.
USAGE
    exit 0
    ;;
  "") ;;
  *) die "unknown argument: $1 (try --help)" ;;
esac

[[ $EUID -ne 0 ]] || die "run ephemeral-setup as your user; it asks for sudo when it needs it"

FLAKE_DIR=${FLAKE_DIR:-/persist/etc/nixos}
[[ -f $FLAKE_DIR/flake.nix ]] || die "no flake at $FLAKE_DIR (set FLAKE_DIR)"

SETTINGS=$(settings_json "$FLAKE_DIR")
if [[ ! -w $SETTINGS ]]; then
  gum confirm "$FLAKE_DIR belongs to root. Make it yours, so it can be edited and kept in git?" ||
    die "nothing changed"
  sudo chown -R "$USER": "$FLAKE_DIR"
fi

get() { jq -r --arg k "$1" '.[$k] // empty' "$SETTINGS"; }

gum style --bold --foreground 212 "Ephemeral Nix setup"
echo

profile=$(gum choose --header "Profile" --selected "$(get profile || true)" \
  "full" "minimal") || exit 0
profile=${profile:-full}

declare -A opt=(
  [extras]="Extra apps and shell tools (Steam, VS Code, Brave, VLC, atuin, fzf)"
  [useOpenSnitch]="OpenSnitch: ask before programs connect out"
  [usePassSshAgent]="Proton Pass SSH agent at login"
  [useControlD]="Control D: DNS over TLS"
)
order=(extras useOpenSnitch usePassSshAgent useControlD)
declare -A on=()

if [[ $profile == full ]]; then
  rows=()
  selected=()
  for k in "${order[@]}"; do
    rows+=("${opt[$k]}")
    current=$(get "$k")
    if [[ $current == true || ($k == useOpenSnitch && -z $current) ]]; then
      selected+=("${opt[$k]}")
    fi
  done
  preselect=()
  if ((${#selected[@]})); then
    preselect=(--selected "$(
      IFS=,
      echo "${selected[*]}"
    )")
  fi
  out=$(printf '%s\n' "${rows[@]}" |
    gum choose --no-limit --header "Options: x to tick, enter when done" "${preselect[@]}") || exit 0
  for k in "${order[@]}"; do
    if grep -qxF "${opt[$k]}" <<<"$out"; then on[$k]=true; else on[$k]=false; fi
  done
fi

vault=$(get passSshVault)
if [[ ${on[usePassSshAgent]:-false} == true ]]; then
  vault=$(gum input --header "Proton Pass vault with your SSH keys" --value "${vault:-Personal}") || exit 0
  case $vault in
    "" | *[[:cntrl:]]* | *'"'* | *'$'* | *'`'* | *\\*)
      die "the vault name can't be empty or have quotes, \$, backticks or backslashes"
      ;;
  esac
fi

args=(--arg profile "$profile")
# shellcheck disable=SC2016 # jq variables
filter='.profile = $profile'
if [[ $profile == full ]]; then
  for k in "${order[@]}"; do
    args+=(--argjson "$k" "${on[$k]}")
    filter+=" | .$k = \$$k"
  done
  if [[ ${on[usePassSshAgent]} == true ]]; then
    args+=(--arg vault "$vault")
    # shellcheck disable=SC2016
    filter+=' | .passSshVault = $vault'
  fi
fi

jq_edit "$SETTINGS" "${args[@]}" "$filter"
echo "Saved $SETTINGS"
echo

gum confirm "Rebuild now? This downloads a lot the first time." || {
  echo "Rebuild later with: sudo nixos-rebuild switch --flake path:$FLAKE_DIR#nixos"
  exit 0
}
sudo nixos-rebuild switch --flake "path:$FLAKE_DIR#nixos"

echo
gum style --bold "Next"
echo "- Log out and back in, so the desktop picks up the new setup."
if [[ $profile == full ]]; then
  echo "- Run ephemeral-apps to pick extra apps."
  if [[ ${on[usePassSshAgent]} == true ]]; then
    echo "- Run pass-cli login if you haven't, then log out and back in once more."
  fi
  if [[ ${on[useControlD]} == true ]]; then
    echo "- Run controld-setup if you haven't entered your Control D resolver id yet."
  fi
fi
