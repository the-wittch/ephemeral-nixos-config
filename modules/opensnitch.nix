{
  flake.modules.nixos.opensnitch =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      nft = lib.getExe pkgs.nftables;
      # new connections out are refused; loopback, DHCP and IPv6 neighbour discovery still work
      guard = pkgs.writeText "opensnitch-down.nft" ''
        destroy table inet opensnitch-down
        table inet opensnitch-down {
          chain output {
            type filter hook output priority filter; policy accept;
            oifname "lo" accept
            udp dport { 67, 547 } accept
            icmpv6 type { nd-router-solicit, nd-neighbor-solicit, nd-neighbor-advert } accept
            ct state new reject
          }
        }
      '';
    in
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

      # The daemon starts after the network is up, so the guard goes up first and opensnitchd's
      # ExecStartPost takes it down once it's filtering.
      boot.kernelModules = [ "nf_tables" ];
      systemd.services.opensnitch-boot-guard = {
        description = "Hold new connections out until OpenSnitch is filtering";
        wantedBy = [ "sysinit.target" ];
        wants = [ "network-pre.target" ];
        after = [ "systemd-modules-load.service" ];
        before = [
          "network-pre.target"
          "opensnitchd.service"
          "sysinit.target"
        ];
        unitConfig.DefaultDependencies = false;
        # it's for the boot; again behind a running daemon, nothing would take it down
        restartIfChanged = false;
        serviceConfig = config.ephemeral.sandbox // {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${nft} -f ${guard}";
          # the rules have to land in the system's network namespace
          PrivateNetwork = false;
          CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
          RestrictAddressFamilies = [ "AF_NETLINK" ];
        };
      };

      # OpenSnitch's queue rule always has the bypass flag (QueueBypass doesn't reach the rules from
      # system-fw.json), so a crashed daemon lets everything out. After a crash the guard holds new
      # connections out until a new daemon is filtering. A clean stop leaves nothing behind, so
      # `systemctl stop opensnitchd` is still the way to get the network back by hand.
      systemd.services.opensnitchd.serviceConfig = {
        RestartSec = 2;
        ExecStopPost = pkgs.writeShellScript "opensnitch-guard-down" ''
          if [[ $SERVICE_RESULT == success ]]; then
            exec ${nft} destroy table inet opensnitch-down
          fi
          ${nft} -f ${guard}
          exec ${nft} destroy table inet opensnitch
        '';
        # the new daemon listens on the queue before it adds the rule, so the rule being there is the
        # sign that it's filtering
        ExecStartPost = pkgs.writeShellScript "opensnitch-guard-up" ''
          for _ in {1..150}; do
            if ${nft} list table inet opensnitch 2>/dev/null | grep -q queue; then
              exec ${nft} destroy table inet opensnitch-down
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
