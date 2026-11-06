{ config, ... }:
let
  hm = config.flake.modules.homeManager;

  common =
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
      # the greeter logs in through greetd
      security.pam.services.greetd.enableGnomeKeyring = true;

      environment.systemPackages = with pkgs; [
        xwayland-satellite
        fuzzel
        brightnessctl
        playerctl
      ];
    };
in
{
  flake.modules.nixos.niri =
    { config, ... }:
    {
      imports = [ common ];

      environment.persistence."/persist".directories = [ "/var/lib/noctalia-greeter" ];

      services.displayManager.noctalia-greeter = {
        passwordlessSyncUsers = [ config.ephemeral.settings.username ];
        settings.appearance.theme_mode = "dark";
      };

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

  flake.modules.nixos."minimal-niri".imports = [ common ];
}
