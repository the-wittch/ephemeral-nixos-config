#!/usr/bin/env bash

set -euo pipefail

case ${1:-} in
  -h | --help)
    cat <<'USAGE'
ephemeral-passwd
Change your login password. passwd doesn't stick here, because users come from
the config; the password lives in /persist/passwords/<you>.
USAGE
    exit 0
    ;;
  "") ;;
  *) die "unknown argument: $1 (try --help)" ;;
esac

[[ $EUID -ne 0 ]] || die "run ephemeral-passwd as your user"
[[ -t 0 ]] || die "ephemeral-passwd needs a terminal to ask for the password"

user=$(id -un)
file=/persist/passwords/$user
sudo test -s "$file" || die "$file doesn't exist, so this machine doesn't keep your password there"

read -rs -p "New password: " one
echo
read -rs -p "New password again: " two
echo
[[ -n $one ]] || die "the password is empty; nothing changed"
[[ $one == "$two" ]] || die "the passwords don't match; nothing changed"

hash=$(printf '%s\n' "$one" | mkpasswd -m yescrypt --stdin)
unset one two
# an empty or broken file here locks you out at the next boot
[[ $hash == "\$y\$"* &&$hash != *[[:space:]:]* ]] || die "mkpasswd didn't give a yescrypt hash; nothing changed"

printf '%s\n' "$hash" | sudo install -m 600 -o root -g root /dev/stdin "$file.new"
sudo mv -f "$file.new" "$file"

# activation copies the file into /etc/shadow at every boot; this saves waiting for one
if printf '%s:%s\n' "$user" "$hash" | sudo chpasswd -e; then
  echo "Password changed. It works now for login, the lock screen and sudo."
else
  echo "Password saved. It takes effect at the next reboot or ephemeral-update."
fi
