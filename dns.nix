{
  lib,
  settings,
  ...
}:

{
  # id is /persist/etc/controld-resolver, mode 600. not in the store.
  services.resolved.enable = settings.useControlD;

  system.activationScripts.controldSecret.text = ''
    if [ -f /persist/etc/controld-resolver ]; then
      chown root:root /persist/etc/controld-resolver
      chmod 600 /persist/etc/controld-resolver
    fi
  '';

  systemd.services.controld-resolver = lib.mkIf settings.useControlD {
    description = "Write Control D config for systemd-resolved";
    requiredBy = [ "systemd-resolved.service" ];
    # resolved starts before sysinit.target, so this can't have the default
    # After=basic.target or boot gets an ordering cycle
    unitConfig.DefaultDependencies = false;
    after = [ "local-fs.target" ];
    before = [
      "systemd-resolved.service"
      "shutdown.target"
    ];
    conflicts = [ "shutdown.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      # reads the id file, writes one drop-in. nothing here may add mount
      # dependencies, since this runs before sysinit.target.
      RuntimeDirectory = "systemd/resolved.conf.d";
      RuntimeDirectoryPreserve = "yes";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateNetwork = true;
      NoNewPrivileges = true;
      CapabilityBoundingSet = [ "CAP_CHOWN" ];
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      RestrictAddressFamilies = [ "AF_UNIX" ];
      RestrictNamespaces = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      SystemCallArchitectures = "native";
    };
    script = ''
      set -euo pipefail
      if [[ ! -f /persist/etc/controld-resolver ]]; then
        echo "missing /persist/etc/controld-resolver" >&2
        exit 1
      fi
      id=$(tr -d '[:space:]' < /persist/etc/controld-resolver)
      if [[ ! $id =~ ^[A-Za-z0-9_-]+$ ]]; then
        echo "bad id in /persist/etc/controld-resolver" >&2
        exit 1
      fi
      # resolved reads this as systemd-resolve; nobody else needs the id
      install -d -m 755 /run/systemd/resolved.conf.d
      conf=/run/systemd/resolved.conf.d/controld.conf
      (
        umask 077
        cat > "$conf.tmp" <<EOF
      [Resolve]
      DNS=76.76.2.22#''${id}.dns.controld.com 2606:1a40::22#''${id}.dns.controld.com
      FallbackDNS=
      Domains=~.
      DNSOverTLS=yes
      EOF
      )
      chown root:systemd-resolve "$conf.tmp"
      chmod 640 "$conf.tmp"
      mv -f "$conf.tmp" "$conf"
    '';
  };
}
