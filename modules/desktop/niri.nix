{ config, ... }:
let
  hm = config.flake.modules.homeManager;
in
{
  flake.modules.nixos.niri =
    { config, pkgs, ... }:
    {
      environment.persistence."/persist".directories = [ "/var/lib/noctalia-greeter" ];

      programs.niri.enable = true;
      programs.noctalia = {
        enable = true;
        systemd.enable = true;
        recommendedServices.enable = true;
      };
      services.displayManager.noctalia-greeter = {
        enable = true;
        passwordlessSyncUsers = [ config.ephemeral.settings.username ];
        settings.appearance.theme_mode = "dark";
      };

      services.gnome.gnome-keyring.enable = true;

      environment.systemPackages = with pkgs; [
        xwayland-satellite
        fuzzel
        brightnessctl
        playerctl
      ];

      home-manager.sharedModules = [ hm.niri ];
    };

  flake.modules.homeManager.niri = {
    programs.noctalia = {
      enable = true;
      settings = {
        theme = {
          mode = "dark";
          shell_mode = "dark";
        };
        shell.greeter_sync.auto_sync = true;
      };
    };
  };

  flake.modules.nixos."minimal-niri" =
    { pkgs, ... }:
    {
      programs.niri.enable = true;
      programs.noctalia = {
        enable = true;
        systemd.enable = true;
        recommendedServices.enable = true;
      };
      services.displayManager.noctalia-greeter.enable = true;

      services.gnome.gnome-keyring.enable = true;
      security.pam.services.login.enableGnomeKeyring = true;
      security.pam.services.greetd.enableGnomeKeyring = true;

      environment.systemPackages = with pkgs; [
        xwayland-satellite
        fuzzel
        brightnessctl
        playerctl
      ];
    };
}
