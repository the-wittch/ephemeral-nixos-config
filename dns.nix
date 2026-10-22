{
  lib,
  settings,
  ...
}:

{
  # id is /persist/etc/controld-resolver, mode 600. not in the store.
  services.resolved.enable = settings.useControlD;

  systemd.services.controld-resolver = lib.mkIf settings.useControlD {
    description = "Write Control D config for systemd-resolved";
    requiredBy = [ "systemd-resolved.service" ];
    before = [ "systemd-resolved.service" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
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
      install -d -m 755 /run/systemd/resolved.conf.d
      cat > /run/systemd/resolved.conf.d/controld.conf <<EOF
      [Resolve]
      DNS=76.76.2.22#''${id}.dns.controld.com 2606:1a40::22#''${id}.dns.controld.com
      FallbackDNS=
      Domains=~.
      DNSOverTLS=yes
      EOF
    '';
  };
}
