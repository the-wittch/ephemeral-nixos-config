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

# menu_profile, menu_encryptedDns, vault_re and custom_dns_re come from modules/settings, by way
# of modules/packages/_prelude.nix
# shellcheck disable=SC2154
profile=$(pick_setting profile "Profile" "$(get profile || true)" "${menu_profile[@]}") || exit 0
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
  # shellcheck disable=SC2154
  [[ $vault =~ ^${vault_re}$ ]] ||
    die "the vault name can't be empty or have quotes, \$, backticks, backslashes or control characters"
fi

dns=$(get encryptedDns)
# Control D needs the full profile
dns_order=()
# shellcheck disable=SC2154
for k in "${menu_encryptedDns[@]}"; do
  [[ $k == controld && $profile != full ]] || dns_order+=("$k")
done
[[ $profile == full && $(get useControlD) == true ]] && dns=controld
dns=$(pick_setting encryptedDns "DNS" "${dns:-none}" "${dns_order[@]}") || exit 0
dns=${dns:-none}

servers=
if [[ $dns == custom ]]; then
  servers=$(gum input --width 0 --header "Servers as address#name, separated by spaces, e.g. 194.242.2.2#dns.mullvad.net" \
    --value "$(jq -r '.customDns // [] | join(" ")' "$SETTINGS")") || exit 0
  [[ -n ${servers// /} ]] || die "no servers given"
  read -ra list <<<"$servers"
  for s in "${list[@]}"; do
    # the name is what the certificate is checked against, so it can't be left out
    # shellcheck disable=SC2154
    [[ $s =~ ^${custom_dns_re}$ ]] ||
      die "$s isn't address#name, such as 194.242.2.2#dns.mullvad.net"
  done
fi

# The TPM key is bound to Secure Boot being on, with this machine's keys; without that, the PIN
# alone would guard the disk.
tpm=$(get tpmUnlock)
tpm=${tpm:-false}
tpm_action=
if tpm_present && [[ $(get secureBoot) == true && $(efi_flag SecureBoot) == 1 ]]; then
  unlock_pass="The passphrase"
  unlock_tpm="A TPM PIN, with the passphrase as the fallback"
  unlock_again="A TPM PIN, enrolled again after a firmware, key or revocation list change"
  choices=("$unlock_pass" "$unlock_tpm")
  current=$unlock_pass
  if [[ $tpm == true ]]; then
    choices+=("$unlock_again")
    current=$unlock_tpm
  fi
  picked=$(printf '%s\n' "${choices[@]}" |
    gum choose --header "Unlocking the disk at boot" --selected "$current") || exit 0
  case $picked in
    "$unlock_tpm")
      [[ $tpm == true ]] || tpm_action=enroll
      tpm=true
      ;;
    "$unlock_again")
      tpm_action=enroll
      tpm=true
      ;;
    *)
      [[ $tpm == false ]] || tpm_action=remove
      tpm=false
      ;;
  esac
elif [[ $tpm == true ]]; then
  echo "TPM unlock stays as it is; changing it needs a TPM and Secure Boot on. ephemeral-doctor says more."
fi

# before saving, so a failure here leaves the settings as they were
if [[ -n $tpm_action ]]; then
  luks=$(luks_device)
  if [[ $tpm_action == enroll ]]; then
    echo "systemd-cryptenroll asks for the disk passphrase, then the new PIN twice."
    tpm_enroll "$luks" || die "the TPM wasn't enrolled; nothing changed"
  else
    echo "systemd-cryptenroll asks for the disk passphrase to remove the TPM slot."
    tpm_remove "$luks" || die "the TPM slot wasn't removed; nothing changed"
  fi
fi

args=(--arg profile "$profile" --arg dns "$dns" --arg servers "$servers" --argjson tpm "$tpm")
# shellcheck disable=SC2016 # jq variables
filter='.profile = $profile | .encryptedDns = (if $dns == "controld" then "none" else $dns end) | if $dns == "custom" then .customDns = ($servers | split(" ") | map(select(. != ""))) else . end | .tpmUnlock = $tpm'
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
if [[ $tpm_action == enroll ]]; then
  echo "- At the next boot the disk asks for the TPM PIN. A wrong one is asked for again until the TPM stops taking guesses; then it asks for the passphrase."
elif [[ $tpm_action == remove ]]; then
  echo "- From the next boot the disk asks for the passphrase again."
fi
