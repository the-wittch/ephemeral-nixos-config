{ config, ... }:
let
  hm = config.flake.modules.homeManager;

  common =
    { pkgs, ... }:
    {
      environment.persistence."/persist".directories = [ "/var/lib/plasmalogin" ];

      services.xserver.enable = true;

      services.desktopManager.plasma6.enable = true;
      services.displayManager.plasma-login-manager.enable = true;

      environment.systemPackages = with pkgs.kdePackages; [
        kate
        ark
        okular
        gwenview
        spectacle
        discover
        partitionmanager
      ];
    };
in
{
  flake.modules.nixos.plasma =
    { lib, pkgs, ... }:
    let
      kdeDark = import ./_kde-dark.nix { inherit lib; };
    in
    {
      imports = [ common ];

      # stylix doesn't theme the login screen
      systemd.tmpfiles.rules = [
        "d /var/lib/plasmalogin/.config 0755 plasmalogin plasmalogin -"
        "L+ /var/lib/plasmalogin/.config/kdeglobals - - - - ${pkgs.writeText "plasmalogin-kdeglobals" kdeDark}"
      ];

      # kwallet is the secret service here
      services.gnome.gnome-keyring.enable = false;

      home-manager.sharedModules = [ hm.plasma ];
    };

  flake.modules.nixos."minimal-plasma" =
    { pkgs, ... }:
    {
      imports = [ common ];

      boot.plymouth = {
        theme = "breeze";
        themePackages = [ pkgs.kdePackages.breeze-plymouth ];
      };

      security.pam.services.plasmalogin.kwallet.enable = true;

      environment.plasma6.excludePackages = [ pkgs.kdePackages.plasma-welcome ];
    };
}
