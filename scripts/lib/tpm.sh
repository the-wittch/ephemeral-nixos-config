# shellcheck shell=bash

# 1 or 0 from the firmware, or nothing when it doesn't have the variable
# shellcheck disable=SC2329 # not every command calls it
efi_flag() {
  od -An -tu1 -j4 -N1 "${EPHEMERAL_ROOT:-}/sys/firmware/efi/efivars/$1-8be4df61-93ca-11d2-aa0d-00e098032b8c" 2>/dev/null | tr -d ' ' || true
}

# shellcheck disable=SC2329
tpm_present() {
  [[ -e ${EPHEMERAL_ROOT:-}/dev/tpmrm0 ]]
}

# shellcheck disable=SC2329
luks_device() {
  local dev
  dev=$(sudo cryptsetup status cryptroot | awk '$1 == "device:" { print $2 }')
  [[ -b $dev ]] || die "could not find the disk behind cryptroot"
  printf '%s\n' "$dev"
}

# PCR 7 is the Secure Boot state: its keys, the revocation list and the key Limine is signed
# with. systemd-cryptenroll asks for the passphrase, then the new PIN twice, and only then
# removes the TPM slot from before.
# shellcheck disable=SC2329
tpm_enroll() {
  sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=7 --tpm2-with-pin=yes --wipe-slot=tpm2 "$1"
}

# shellcheck disable=SC2329
tpm_remove() {
  sudo systemd-cryptenroll --wipe-slot=tpm2 "$1"
}
