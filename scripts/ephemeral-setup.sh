#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
ephemeral-setup
Switch between the minimal and full profile and turn the main options on or off,
then rebuild. Run it again any time to change them.
USAGE
}

case ${1:-} in
  -h | --help)
    usage
    exit 0
    ;;
  "") ;;
  *) usage_error ;;
esac

[[ $EUID -ne 0 ]] || die "run ephemeral-setup as your user; it asks for sudo when it needs it"
require_tty
flake=$(require_flake)
refuse_secret_files "$flake"

SETTINGS=$(settings_json "$flake")
if flake_needs_owner "$flake"; then
  gum confirm "$flake belongs to root. Make it yours, so it can be edited and kept in git?" ||
    die "nothing changed"
  sudo chown -R "$USER": "$flake"
fi

get() { jq -r --arg k "$1" '.[$k] // empty' "$SETTINGS"; }

gum style --bold --foreground 212 "Ephemeral Nix setup"
echo

profile=$(gum choose --header "Profile" --selected "$(get profile || true)" \
  "full" "minimal") || exit 0
profile=${profile:-full}

declare -A opt=(
  [extras]="Extra shell tools (atuin, fzf, bat, fastfetch, comma)"
  [useOpenSnitch]="OpenSnitch: ask before programs connect out"
  [usePassSshAgent]="Proton Pass SSH agent at login"
)
order=(extras useOpenSnitch usePassSshAgent)
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

declare -A dns_label=(
  [none]="The network's DNS (not encrypted)"
  [cloudflare]="Cloudflare (no filtering)"
  [quad9]="Quad9 (blocks malware)"
  [adguard]="AdGuard (blocks ads and trackers)"
  [controld]="Control D (your own resolver id)"
  [custom]="Other: your own DNS over TLS servers"
)
dns_order=(none cloudflare quad9 adguard)
dns=$(get encryptedDns)
if [[ $profile == full ]]; then
  dns_order+=(controld)
  [[ $(get useControlD) == true ]] && dns=controld
fi
dns_order+=(custom)
labels=()
for k in "${dns_order[@]}"; do labels+=("${dns_label[$k]}"); done
picked=$(printf '%s\n' "${labels[@]}" |
  gum choose --header "DNS" --selected "${dns_label[${dns:-none}]}") || exit 0
dns=none
for k in "${dns_order[@]}"; do [[ $picked == "${dns_label[$k]}" ]] && dns=$k; done

servers=
if [[ $dns == custom ]]; then
  servers=$(gum input --width 0 --header "Servers as address#name, separated by spaces, e.g. 194.242.2.2#dns.mullvad.net" \
    --value "$(jq -r '.customDns // [] | join(" ")' "$SETTINGS")") || exit 0
  [[ -n ${servers// /} ]] || die "no servers given"
  read -ra list <<<"$servers"
  for s in "${list[@]}"; do
    # the name is what the certificate is checked against, so it can't be left out
    [[ $s =~ ^[0-9A-Fa-f.:]+#[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$ ]] ||
      die "$s isn't address#name, such as 194.242.2.2#dns.mullvad.net"
  done
fi

args=(--arg profile "$profile" --arg dns "$dns" --arg servers "$servers")
# shellcheck disable=SC2016 # jq variables
filter='.profile = $profile | .encryptedDns = (if $dns == "controld" then "none" else $dns end) | if $dns == "custom" then .customDns = ($servers | split(" ") | map(select(. != ""))) else . end'
# only one of them can have the DNS; on the small install Control D is ignored, so it's left alone there
if [[ $profile == full ]]; then
  # shellcheck disable=SC2016
  filter+=' | .useControlD = ($dns == "controld")'
elif [[ $dns != none ]]; then
  filter+=' | .useControlD = false'
fi
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
  echo "Rebuild later with: ephemeral-update"
  exit 0
}
ephemeral-update

echo
gum style --bold "Next"
echo "- Log out and back in, so the desktop picks up the new setup."
if [[ $profile == full ]]; then
  echo "- Run ephemeral-apps to pick extra apps."
  if [[ ${on[usePassSshAgent]} == true ]]; then
    echo "- Run pass-cli login if you haven't, then log out and back in once more."
  fi
  if [[ $dns == controld ]]; then
    echo "- Run controld-setup if you haven't entered your Control D resolver id yet."
  fi
fi
