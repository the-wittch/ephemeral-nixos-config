# shellcheck shell=bash
# shellcheck disable=SC2154 # plasma_run, steam_shortcuts and launchers are set by the lines Nix puts before this
# The handheld's one login, from greetd: Game Mode, or Plasma when Steam's "Switch to Desktop"
# asked for it, then back to Game Mode, as on SteamOS. A loop rather than a new login each time,
# so the session stays a user's, not a greeter's, without a password to log in with.

next_file=${XDG_STATE_HOME:-$HOME/.local/state}/ephemeral/next-session

while true; do
  next=gamescope
  if [[ -f $next_file ]]; then
    next=$(<"$next_file")
    # Desktop mode is for one session; the next boot or logout is Game Mode again
    rm -f -- "$next_file"
  fi

  # Steam writes its own copy of the shortcuts back when it exits, so they go in between
  "$steam_shortcuts" "$launchers" || true

  export EPHEMERAL_SESSION=$next
  case $next in
    plasma)
      export XDG_SESSION_DESKTOP=KDE XDG_CURRENT_DESKTOP=KDE
      "$plasma_run" startplasma-wayland || sleep 2
      ;;
    *)
      export XDG_SESSION_DESKTOP=gamescope XDG_CURRENT_DESKTOP=gamescope
      # a session that won't start shouldn't spin
      steam-gamescope || sleep 2
      ;;
  esac
  unset XDG_SESSION_DESKTOP XDG_CURRENT_DESKTOP
done
