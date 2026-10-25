#!/usr/bin/env bash

set -euo pipefail

user=${GREETER_SYNC_USER:-}
desktop=${GREETER_SYNC_DESKTOP:-}
if [[ ! $user =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
  echo "GREETER_SYNC_USER is missing or not a username" >&2
  exit 1
fi
case $desktop in
  gnome | plasma | niri) ;;
  *)
    echo "GREETER_SYNC_DESKTOP must be gnome, plasma, or niri" >&2
    exit 1
    ;;
esac

home=/home/$user
if [[ ! -d $home ]]; then
  exit 0
fi

uid=$(id -u "$user")
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
  if (( (other & 4) == 0 )); then
    return 1
  fi
  cur=$(dirname "$path")
  while [[ $cur != / ]]; do
    mode=$(stat -c %a "$cur")
    other=$((10#$mode % 10))
    if (( (other & 1) == 0 )); then
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
  if [[ -f $dest ]] && cmp -s "$tmp" "$dest" && is_image "$dest"; then
    rm -f "$tmp"
    chmod 644 "$dest"
    chown root:root "$dest"
    return 0
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
  copy_public "$src" "$bg_dir/$dest_name"
  printf '%s\n' "$bg_dir/$dest_name"
}

toml_key() {
  local file=$1 key=$2 line value
  [[ -f $file ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line =~ ^[[:space:]]*# ]] && continue
    [[ $line =~ ^[[:space:]]*${key}[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
    value=$(unquote "${BASH_REMATCH[1]}")
    value=${value%$'\r'}
    printf '%s' "$value"
    return 0
  done <"$file"
}

plasma_image() {
  local file=$1 line value found=""
  [[ -f $file ]] || return 0
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == Image=* ]] || continue
    value=${line#Image=}
    value=${value%$'\r'}
    value=$(unquote "$value")
    [[ -n $value ]] || continue
    found=$value
  done <"$file"
  printf '%s' "$found"
}

noctalia_avatar() {
  local value file
  for file in "$home/.local/state/noctalia/settings.toml" "$home/.config/noctalia/config.toml"; do
    value=$(toml_key "$file" avatar_path)
    [[ -n $value ]] || continue
    if [[ $value == \~/* ]]; then
      value=$home/${value#\~/}
    fi
    printf '%s\n' "$value"
    return 0
  done
}

sync_gnome_wallpaper() {
  local uri dark_uri options light dark keys tmpdb
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

  if [[ $light != "$bg_dir/$user" ]]; then
    rm -f "$bg_dir/$user"
  fi
  if [[ $dark != "$bg_dir/$user-dark" ]]; then
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
}

sync_plasma_wallpaper() {
  local raw light conf tmp owns=0 line
  raw=$(plasma_image "$home/.config/kscreenlockerrc")
  if [[ -z $raw ]]; then
    raw=$(plasma_image "$home/.config/plasma-org.kde.plasma.desktop-appletsrc")
  fi
  case $raw in
    *#dark) raw=${raw%#dark} ;;
    *#light) raw=${raw%#light} ;;
    *#day-night) raw=${raw%#day-night} ;;
  esac
  if [[ -n $raw && $raw != file://* && $raw == /* ]]; then
    raw="file://$raw"
  fi
  if [[ $raw == file:///* ]]; then
    light=$(chosen_file "$raw" "$user")
  else
    light=""
  fi

  if [[ $light != "$bg_dir/$user" ]]; then
    rm -f "$bg_dir/$user"
  fi

  conf=/etc/plasmalogin.conf
  if [[ -f $conf ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      [[ $line == '# published by greeter-sync' ]] && owns=1
    done <"$conf"
  fi
  if [[ -z $light ]]; then
    if [[ $owns -eq 1 ]]; then
      rm -f "$conf"
    fi
    return 0
  fi
  if [[ -f $conf && $owns -eq 0 ]]; then
    echo "not replacing $conf" >&2
    return 0
  fi

  tmp=$(mktemp /etc/plasmalogin.conf.XXXXXX)
  {
    printf '%s\n' "# published by greeter-sync"
    printf '%s\n' "[Greeter]"
    printf '%s\n' "WallpaperPluginId=org.kde.image"
    printf '\n%s\n' "[Greeter][Wallpaper][org.kde.image][General]"
    printf 'Image=file://%s\n' "$light"
  } >"$tmp"
  chmod 644 "$tmp"
  chown root:root "$tmp"
  mv -f "$tmp" "$conf"
}

sync_wallpaper() {
  case $desktop in
    gnome) sync_gnome_wallpaper ;;
    plasma) sync_plasma_wallpaper ;;
    niri) ;;
  esac
}

sync_avatar() {
  local face src prop current candidate
  local -a candidates=()
  case $desktop in
    plasma)
      candidates=("$home/.face.icon" "$home/.face")
      ;;
    niri)
      candidate=$(noctalia_avatar || true)
      if [[ -n $candidate ]]; then
        candidates+=("$candidate")
      fi
      candidates+=("$home/.face.icon" "$home/.face")
      ;;
    *)
      candidates=("$home/.face" "$home/.face.icon")
      ;;
  esac

  src=""
  for face in "${candidates[@]}"; do
    [[ -f $face ]] || continue
    src=$(publishable "$face")
    [[ -n $src ]] && break
  done
  [[ -n $src ]] || return 0

  prop=$(
    busctl get-property org.freedesktop.Accounts \
      "/org/freedesktop/Accounts/User${uid}" \
      org.freedesktop.Accounts.User IconFile 2>/dev/null || true
  )
  current=$(unquote "${prop#s }")
  if [[ $current == "/var/lib/AccountsService/icons/$user" ]] &&
    [[ -f $current ]] && cmp -s "$src" "$current"; then
    return 0
  fi

  runuser -u "$user" -- busctl call org.freedesktop.Accounts \
    "/org/freedesktop/Accounts/User${uid}" \
    org.freedesktop.Accounts.User SetIconFile s "$src"
}

sync_wallpaper
if ! sync_avatar; then
  echo "avatar was not published" >&2
fi
