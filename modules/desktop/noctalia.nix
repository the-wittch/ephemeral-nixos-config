{ config, ... }:
let
  hm = config.flake.modules.homeManager;
  nixos = config.flake.modules.nixos;
in
{
  # the Noctalia shell and greeter, shared by niri and Umbriel
  flake.modules.nixos.noctalia-base =
    { pkgs, ... }:
    {
      programs.noctalia = {
        enable = true;
        systemd.enable = true;
        recommendedServices.enable = true;
      };
      services.displayManager.noctalia-greeter.enable = true;

      services.gnome.gnome-keyring.enable = true;
      # the greeter logs in through greetd
      security.pam.services.greetd.enableGnomeKeyring = true;

      environment.systemPackages = with pkgs; [
        brightnessctl
        playerctl
      ];
    };

  flake.modules.nixos.noctalia =
    { config, ... }:
    {
      imports = [ nixos.noctalia-base ];
      environment.persistence."/persist".directories = [ "/var/lib/noctalia-greeter" ];

      services.displayManager.noctalia-greeter = {
        passwordlessSyncUsers = [ config.ephemeral.settings.username ];
        settings.appearance.theme_mode = "dark";
      };

      home-manager.sharedModules = [ hm.noctalia ];
    };

  flake.modules.homeManager.noctalia = {
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
}
