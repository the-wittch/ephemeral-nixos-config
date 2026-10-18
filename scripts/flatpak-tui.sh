#!/usr/bin/env bash
# flatpak-apps. user installs, don't sudo.

set -euo pipefail

if ! command -v gum >/dev/null || ! command -v flatpak >/dev/null; then
  echo "Need gum and flatpak on PATH." >&2
  echo "  Install gum and flatpak, then re-run." >&2
  echo "  NixOS: rebuild so the flatpak-apps package is installed, then run: flatpak-apps" >&2
  exit 1
fi

# id|display name
APPS=(
  "com.github.tchx84.Flatseal|Flatseal"
  "com.mattjakeman.ExtensionManager|Extension Manager"
  "it.mijorus.gearlever|Gear Lever"
  "com.heroicgameslauncher.hgl|Heroic"
  "net.lutris.Lutris|Lutris"
  "org.prismlauncher.PrismLauncher|Prism Launcher"
  "org.mozilla.thunderbird|Thunderbird"
  "org.inkscape.Inkscape|Inkscape"
  "org.kde.krita|Krita"
  "com.borgbase.Vorta|Vorta"
  "org.gnome.World.PikaBackup|Pika Backup"
  "io.gitlab.news_flash.NewsFlash|Newsflash"
  "org.remmina.Remmina|Remmina"
)

is_installed() {
  flatpak info "$1" &>/dev/null
}

ensure_user_dirs() {
  # flatpak errors if index.theme isn't there
  local hicolor="$HOME/.local/share/icons/hicolor"
  mkdir -p "$hicolor" "$HOME/.local/share/flatpak"
  if [[ ! -f $hicolor/index.theme ]]; then
    cat >"$hicolor/index.theme" <<'EOF'
[Icon Theme]
Name=Hicolor
Comment=Fallback icon theme
Directories=
EOF
  fi
}

ensure_flathub() {
  # --user needs its own flathub remote. the system one isn't enough.
  if ! flatpak remote-list --user --columns=name 2>/dev/null | grep -qx flathub; then
    gum style --foreground 212 "Adding Flathub remote (user)…"
    flatpak remote-add --user --if-not-exists flathub \
      https://dl.flathub.org/repo/flathub.flatpakrepo
  fi
  gum style --foreground 240 "Refreshing Flathub appstream…"
  flatpak update --appstream --user >/dev/null
}

ensure_user_dirs
ensure_flathub

gum style --bold --foreground 212 "FlatHub apps"
echo

status_lines=()
missing_labels=()
missing_ids=()

for entry in "${APPS[@]}"; do
  id=${entry%%|*}
  name=${entry#*|}
  if is_installed "$id"; then
    status_lines+=("$(printf '✓ %-22s %s' "$name" "$id")")
  else
    status_lines+=("$(printf '· %-22s %s' "$name" "$id")")
    missing_labels+=("$name  ($id)")
    missing_ids+=("$id")
  fi
done

printf '%s\n' "${status_lines[@]}" | gum style --border rounded --padding "0 1" --border-foreground 240
echo

if [[ ${#missing_ids[@]} -eq 0 ]]; then
  gum style --foreground 2 "Everything in the list is already installed."
  exit 0
fi

gum style --foreground 240 "${#missing_ids[@]} not installed. Select apps to install (Enter confirms, Esc cancels)."
echo

selected=$(
  printf '%s\n' "${missing_labels[@]}" |
    gum choose --no-limit --height 16 --header "Install from Flathub"
) || {
  gum style "Cancelled."
  exit 0
}

[[ -z $selected ]] && {
  gum style "Nothing selected."
  exit 0
}

while IFS= read -r line; do
  [[ -z $line ]] && continue
  id=${line##* (}
  id=${id%)}
  name=${line%%  (*}
  gum style --bold "Installing $name…"
  flatpak install -y --noninteractive --user flathub "$id"
done <<<"$selected"

gum style --foreground 2 "Done."
echo
gum style --bold "Current status"
for entry in "${APPS[@]}"; do
  id=${entry%%|*}
  name=${entry#*|}
  if is_installed "$id"; then
    printf '✓ %s\n' "$name"
  else
    printf '· %s\n' "$name"
  fi
done
