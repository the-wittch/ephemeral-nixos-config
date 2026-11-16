{
  flake.modules.nixos.opensnitch =
    { lib, pkgs, ... }:
    {
      environment.persistence."/persist".directories = [ "/var/lib/opensnitch" ];
      environment.systemPackages = [ pkgs.opensnitch-ui ];

      services.opensnitch = {
        enable = true;
        settings = {
          DefaultAction = "deny";
          InterceptUnknown = true;
        };
      };

      # OpenSnitch's queue rule always has the bypass flag (QueueBypass doesn't reach the rules from
      # system-fw.json), so a crashed daemon lets everything out. After a crash this table holds new
      # connections out until a new daemon is filtering. A clean stop leaves nothing behind, so
      # `systemctl stop opensnitchd` is still the way to get the network back by hand.
      systemd.services.opensnitchd.serviceConfig = {
        RestartSec = 2;
        ExecStopPost = pkgs.writeShellScript "opensnitch-guard-down" ''
          if [[ $SERVICE_RESULT == success ]]; then
            exec ${lib.getExe pkgs.nftables} destroy table inet opensnitch-down
          fi
          ${lib.getExe pkgs.nftables} -f - <<'EOF'
          destroy table inet opensnitch
          table inet opensnitch-down {
            chain output {
              type filter hook output priority filter; policy accept;
              oifname "lo" accept
              ct state new reject
            }
          }
          EOF
        '';
        # the new daemon listens on the queue before it adds the rule, so the rule being there is the
        # sign that it's filtering
        ExecStartPost = pkgs.writeShellScript "opensnitch-guard-up" ''
          for _ in {1..150}; do
            if ${lib.getExe pkgs.nftables} list table inet opensnitch 2>/dev/null | grep -q queue; then
              exec ${lib.getExe pkgs.nftables} destroy table inet opensnitch-down
            fi
            sleep 0.2
          done
          echo "OpenSnitch didn't add its filter rule within 30 seconds" >&2
          exit 1
        '';
      };

      environment.etc."xdg/autostart/opensnitch-ui.desktop" = {
        text = ''
          [Desktop Entry]
          Type=Application
          Name=OpenSnitch
          Exec=${lib.getExe pkgs.opensnitch-ui} --background
          Icon=opensnitch-ui
          Comment=Interactive application firewall
          Terminal=false
          Categories=System;Security;Network;
          X-GNOME-Autostart-Delay=3
          X-GNOME-Autostart-enabled=true
        '';
      };
    };
}
