#!/usr/bin/env bash
# Show the user's GNOME wallpaper on the GDM login screen.
# Runs as root. Everything read from the user's home is read as the user.

set -euo pipefail

user=${GREETER_SYNC_USER:-}
if [[ ! $user =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  echo "GREETER_SYNC_USER is missing or not a username" >&2
  exit 1
fi

home=/home/$user
if [[ ! -d $home ]]; then
  exit 0
fi

bg_dir=/var/lib/AccountsService/backgrounds
greeter_db=/var/lib/gdm/greeter-db
max_bytes=$((50 * 1024 * 1024))

unquote() {
  local s=$1
  if [[ $s == \'*\' || $s == \"*\" ]]; then
    s=${s:1:${#s}-2}
  fi
  printf '%s' "$s"
}

urldecode() {
  local encoded=$1 out="" hex
  while [[ $encoded == *%* ]]; do
    out+=${encoded%%\%*}
    encoded=${encoded#*%}
    hex=${encoded:0:2}
    encoded=${encoded:2}
    if [[ ! $hex =~ ^[0-9A-Fa-f]{2}$ || $hex == 00 ]]; then
      return 1
    fi
    # shellcheck disable=SC2059
    out+=$(printf "\\x$hex")
  done
  printf '%s' "$out$encoded"
}

dconf_get() {
  local raw
  raw=$(
    runuser -u "$user" -- env -u DBUS_SESSION_BUS_ADDRESS \
      HOME="$home" \
      XDG_CONFIG_HOME="$home/.config" \
      dconf read "$1" 2>/dev/null || true
  )
  raw=${raw%$'\n'}
  unquote "$raw"
}

greeter_can_read() {
  local path=$1 mode other cur
  [[ -f $path ]] || return 1
  mode=$(stat -c %a "$path")
  other=$((10#$mode % 10))
  if (((other & 4) == 0)); then
    return 1
  fi
  cur=$(dirname "$path")
  while [[ $cur != / ]]; do
    mode=$(stat -c %a "$cur")
    other=$((10#$mode % 10))
    if (((other & 1) == 0)); then
      return 1
    fi
    cur=$(dirname "$cur")
  done
}

is_image() {
  local sig
  sig=$(od -An -N 12 -t x1 -- "$1" | tr -d ' \n')
  [[ $sig == 89504e47* ]] && return 0
  [[ $sig == ffd8ff* ]] && return 0
  [[ $sig == 47494638* ]] && return 0
  # RIFF....WEBP
  [[ $sig == 52494646????????57454250 ]] && return 0
  return 1
}

user_can_read() {
  runuser -u "$user" -- test -r "$1"
}

# prints the resolved path if it may be shown on the login screen
publishable() {
  local path=$1 real
  [[ -n $path ]] || return 0
  real=$(readlink -f -- "$path") || return 0
  [[ -f $real && $real != *$'\n'* && $real != *\'* ]] || return 0
  case $real in
    "$home"/.ssh/* | "$home"/.gnupg/* | "$home"/.pki/* | "$home"/.password-store/* | "$home"/.local/share/keyrings/*)
      return 0
      ;;
    "$home"/*) ;;
    *)
      greeter_can_read "$real" || return 0
      case $real in
        /etc/* | /persist/etc/* | /persist/passwords/* | /proc/* | /sys/* | /dev/* | /run/* | /var/lib/AccountsService/users/*)
          return 0
          ;;
      esac
      ;;
  esac
  user_can_read "$real" || return 0
  is_image "$real" || return 0
  printf '%s\n' "$real"
}

copy_public() {
  local src=$1 dest=$2 size dir tmp
  dir=$(dirname "$dest")
  install -d -m 0755 -o root -g root "$dir"
  tmp=$(mktemp "$dir/.publish.XXXXXX")
  # read as the user so a swapped symlink can't reach root-only files
  if ! runuser -u "$user" -- head -c "$((max_bytes + 1))" -- "$src" >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  size=$(stat -c %s "$tmp")
  if ((size == 0 || size > max_bytes)); then
    rm -f "$tmp"
    echo "not publishing $src" >&2
    return 1
  fi
  if ! is_image "$tmp"; then
    rm -f "$tmp"
    echo "not an image: $src" >&2
    return 1
  fi
  chmod 644 "$tmp"
  chown root:root "$tmp"
  mv -f "$tmp" "$dest"
}

# prints the path the greeter should use, or nothing
chosen_file() {
  local uri=$1 dest_name=$2 path src
  [[ $uri == file:///* ]] || return 0
  path=$(urldecode "${uri#file://}") || return 0
  src=$(publishable "$path")
  [[ -n $src ]] || return 0
  # store paths can be garbage-collected
  if greeter_can_read "$src" && [[ $src != /nix/store/* ]]; then
    printf '%s\n' "$src"
    return 0
  fi
  copy_public "$src" "$bg_dir/$dest_name" || return 0
  printf '%s\n' "$bg_dir/$dest_name"
}

uri=$(dconf_get /org/gnome/desktop/background/picture-uri)
if [[ -z $uri ]]; then
  uri=$(dconf_get /org/gnome/desktop/screensaver/picture-uri)
fi
dark_uri=$(dconf_get /org/gnome/desktop/background/picture-uri-dark)
options=$(dconf_get /org/gnome/desktop/background/picture-options)
if [[ ! $options =~ ^[a-z-]*$ ]]; then
  options=""
fi

light=$(chosen_file "$uri" "$user")
dark=$(chosen_file "$dark_uri" "$user-dark")
if [[ -z $light ]]; then
  light=$dark
fi
if [[ -z $dark ]]; then
  dark=$light
fi

if [[ $light != "$bg_dir/$user" && $dark != "$bg_dir/$user" ]]; then
  rm -f "$bg_dir/$user"
fi
if [[ $light != "$bg_dir/$user-dark" && $dark != "$bg_dir/$user-dark" ]]; then
  rm -f "$bg_dir/$user-dark"
fi

mkdir -p /var/lib/gdm
keys=$(mktemp -d)
if [[ -n $light ]]; then
  {
    printf '%s\n' "[org/gnome/desktop/background]"
    printf "picture-uri='file://%s'\n" "$light"
    printf "picture-uri-dark='file://%s'\n" "$dark"
    if [[ -n $options ]]; then
      printf "picture-options='%s'\n" "$options"
    fi
    printf '\n%s\n' "[org/gnome/desktop/screensaver]"
    printf "picture-uri='file://%s'\n" "$light"
    if [[ -n $options ]]; then
      printf "picture-options='%s'\n" "$options"
    fi
  } >"$keys/background"
fi
tmpdb=$(mktemp /var/lib/gdm/greeter-db.XXXXXX)
dconf compile "$tmpdb" "$keys"
rm -rf "$keys"
chmod 644 "$tmpdb"
chown root:root "$tmpdb"
mv -f "$tmpdb" "$greeter_db"
