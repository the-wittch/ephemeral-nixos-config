# libvirt qemu hook: <guest> <operation> <sub-operation>, the domain XML on stdin.
# Only acts when the guest is given the GPU the host booted on. libvirt binds it to
# vfio-pci and back itself (managed host devices); this frees it first and restores
# the desktop afterwards.

guest=$1 op=$2 sub=$3
case "$op/$sub" in
  prepare/begin | release/end) ;;
  *) exit 0 ;;
esac

state=/run/ephemeral-gpu-passthrough
log() { echo "gpu-passthrough: $guest: $*" >&2; }
field() { xmllint --xpath "string((//devices/hostdev[@type='pci'])[$1]/source/address/@$2)" - <<<"$xml"; }

gpu=""
if [[ $op == prepare ]]; then
  xml=$(cat)
  count=$(xmllint --xpath "count(//devices/hostdev[@type='pci'])" - <<<"$xml")
  for ((i = 1; i <= count; i++)); do
    dev=$(printf '%04x:%02x:%02x.%x' "$(field "$i" domain)" "$(field "$i" bus)" "$(field "$i" slot)" "$(field "$i" function)")
    if [[ $(cat "/sys/bus/pci/devices/$dev/boot_vga" 2>/dev/null) == 1 ]]; then
      gpu=$dev
      break
    fi
  done
  [[ -n $gpu ]] || exit 0
elif [[ -f $state/$guest ]]; then
  gpu=$(cat "$state/$guest")
else
  exit 0
fi

modules_for() {
  case $1 in
    nvidia) echo nvidia_drm nvidia_uvm nvidia_modeset nvidia ;;
    *) echo "$1" ;;
  esac
}

restore() {
  local driver
  driver=$(cat "$state/$guest.driver" 2>/dev/null || true)
  if [[ -n $driver ]]; then
    # shellcheck disable=SC2046
    modprobe -a $(modules_for "$driver" | tr ' ' '\n' | tac) || log "couldn't load $driver"
  fi
  for vt in /sys/class/vtconsole/vtcon*/bind; do echo 1 >"$vt" 2>/dev/null || true; done
  systemctl start display-manager.service || log "couldn't start the display manager"
  rm -f "$state/$guest" "$state/$guest.driver"
}

if [[ $op == release ]]; then
  log "giving $gpu back to the host"
  restore
  exit 0
fi

log "taking $gpu from the host"
mkdir -p "$state"
echo "$gpu" >"$state/$guest"
driver=$(basename "$(readlink "/sys/bus/pci/devices/$gpu/driver" 2>/dev/null)" 2>/dev/null || true)
[[ $driver == vfio-pci ]] && driver=""
echo "$driver" >"$state/$guest.driver"

# a failed start leaves the host without a screen, so bring it back
trap 'log "failed, restoring the desktop"; restore' ERR
set -E

for s in $(loginctl list-sessions --no-legend | cut -d' ' -f1); do
  case $(loginctl show-session "$s" -p Type --value) in
    wayland | x11) loginctl terminate-session "$s" ;;
  esac
done
systemctl stop display-manager.service
for vt in /sys/class/vtconsole/vtcon*/bind; do echo 0 >"$vt" 2>/dev/null || true; done

if [[ -n $driver ]]; then
  # shellcheck disable=SC2046
  for try in 1 2 3 4 5 6 7 8 9 10; do
    modprobe -r $(modules_for "$driver") 2>/dev/null && break
    ((try < 10)) || {
      log "couldn't unload $driver; still in use by:"
      fuser -v /dev/dri/* /dev/nvidia* 2>&1 | sed 's/^/  /' >&2 || true
      false
    }
    # anything left holding the GPU from the ended session
    ((try >= 3)) && fuser -sk -TERM /dev/dri/* /dev/nvidia* 2>/dev/null || true
    ((try >= 6)) && fuser -sk -KILL /dev/dri/* /dev/nvidia* 2>/dev/null || true
    sleep 1
  done
fi
modprobe vfio-pci
