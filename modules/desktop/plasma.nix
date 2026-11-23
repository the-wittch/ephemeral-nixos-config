{ config, ... }:
let
  hm = config.ephemeral.aspects.homeManager;
  inherit (config.ephemeral.aspects) nixos;

  common =
    { pkgs, ... }:
    {
      imports = [ nixos.graphical ];

      # the greeter writes its state there, as the package's own tmpfiles rule sets it up
      preservation.preserveAt."/persist".directories = [
        {
          directory = "/var/lib/plasmalogin";
          user = "plasmalogin";
          group = "plasmalogin";
          mode = "0750";
        }
      ];

      services.xserver.enable = true;

      services.desktopManager.plasma6.enable = true;
      services.displayManager.plasma-login-manager.enable = true;

      environment.systemPackages = with pkgs.kdePackages; [
        kate
        ark
        okular
        gwenview
        spectacle
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
      imports = [
        common
        nixos.home-manager
      ];

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

      environment.plasma6.excludePackages = [ pkgs.kdePackages.plasma-welcome ];
      # the full profile gets these from ephemeral-apps
      environment.systemPackages = with pkgs.kdePackages; [
        discover
        partitionmanager
      ];
    };
}
