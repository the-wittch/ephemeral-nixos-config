# shellcheck shell=bash
# shellcheck disable=SC2154 # plasma_run, steam_shortcuts and launchers are set by the lines Nix puts before this
# The handheld's one login, from greetd: Game Mode, or Plasma when Steam's "Switch to Desktop"
# asked for it, then back to Game Mode, as on SteamOS. A loop rather than a new login each time,
# so the session stays a user's, not a greeter's, without a password to log in with.

state=${XDG_STATE_HOME:-$HOME/.local/state}/ephemeral
next_file=$state/next-session
# Game Mode ending this soon, without anyone asking for the desktop, is a start that failed
quick=60
failures=0

while true; do
  next=gamescope
  if [[ -f $next_file ]]; then
    next=$(<"$next_file")
    # Desktop mode is for one session; the next boot or logout is Game Mode again
    rm -f -- "$next_file"
  fi
  # three failed starts in a row: the desktop once, which says why, rather than a black screen
  # coming and going
  if ((failures >= 3)); then
    next=plasma
    failures=0
    mkdir -p "$state"
    printf '%s\n' "Game Mode stopped three times as it started. See why with: journalctl -b --user" \
      >"$state/game-mode-failed"
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
      started=$SECONDS
      # a session that won't start shouldn't spin
      steam-gamescope || sleep 2
      if ((SECONDS - started < quick)) && [[ ! -f $next_file ]]; then
        failures=$((failures + 1))
      else
        failures=0
      fi
      ;;
  esac
  unset XDG_SESSION_DESKTOP XDG_CURRENT_DESKTOP
done
