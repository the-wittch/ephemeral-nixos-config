# shellcheck shell=bash
# What Steam runs for "Switch to Desktop", and the Return to Game Mode launcher runs to go back:
# say which session is next, then end this one, and the session loop starts it.

case ${1:-} in
  plasma* | desktop) next=plasma ;;
  gamescope) next=gamescope ;;
  *)
    echo "usage: steamos-session-select plasma|gamescope" >&2
    exit 2
    ;;
esac

state=${XDG_STATE_HOME:-$HOME/.local/state}/ephemeral
mkdir -p "$state"
printf '%s\n' "$next" >"$state/next-session"

case ${EPHEMERAL_SESSION:-} in
  plasma) dbus-send --session --type=method_call --dest=org.kde.Shutdown /Shutdown org.kde.Shutdown.logout ;;
  gamescope) steam -shutdown ;;
esac
