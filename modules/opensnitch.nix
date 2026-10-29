{
  flake.modules.nixos.full =
    { lib, pkgs, ... }:
    {
      environment.persistence."/persist".directories = [ "/var/lib/opensnitch" ];

      services.opensnitch = {
        enable = true;
        settings = {
          DefaultAction = "deny";
          InterceptUnknown = true;
        };
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
