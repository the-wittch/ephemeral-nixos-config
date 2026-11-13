{ config, ... }:
let
  hm = config.ephemeral.aspects.homeManager;
  nixos = config.ephemeral.aspects.nixos;
in
{
  flake.modules.nixos.noctalia-base =
    { lib, pkgs, ... }:
    {
      programs.noctalia = {
        enable = true;
        systemd.enable = true;
        recommendedServices.enable = true;
      };
      services.displayManager.noctalia-greeter.enable = true;
      environment.persistence."/persist".directories = [ "/var/lib/noctalia-greeter" ];

      services.gnome.gnome-keyring.enable = true;
      # the greeter logs in through greetd
      security.pam.services.greetd.enableGnomeKeyring = true;

      # gvfs gives Nautilus the trash, network shares and phones
      services.gvfs.enable = true;

      # the apps GNOME comes with, so files in Nautilus open in something
      environment.systemPackages = with pkgs; [
        brightnessctl
        playerctl
        nautilus
        loupe
        papers
        gnome-text-editor
        file-roller
        gnome-calculator
        gst-thumbnailers
      ];

      # VS Code and browsers claim folders, text and images too, and with no default either could open them
      xdg.mime.defaultApplications =
        lib.genAttrs [ "image/png" "image/jpeg" "image/gif" "image/webp" "image/avif" "image/svg+xml" ] (
          _: "org.gnome.Loupe.desktop"
        )
        // lib.genAttrs [
          "application/zip"
          "application/x-tar"
          "application/x-compressed-tar"
          "application/x-7z-compressed"
        ] (_: "org.gnome.FileRoller.desktop")
        // {
          "inode/directory" = "org.gnome.Nautilus.desktop";
          "application/pdf" = "org.gnome.Papers.desktop";
          "text/plain" = "org.gnome.TextEditor.desktop";
        };
    };

  flake.modules.nixos.noctalia = {
    imports = [
      nixos.noctalia-base
      nixos.home-manager
    ];

    # set here, since syncing it from the shell runs a root helper
    services.displayManager.noctalia-greeter.settings.appearance.theme_mode = "dark";

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
        shell.greeter_sync.auto_sync = false;
        # Noctalia's idle lock is off by default; Plasma and GNOME lock after a few idle minutes
        lockscreen = {
          enabled = true;
          lock_before_suspend = true;
        };
        idle.behavior.lock = {
          enabled = true;
          action = "lock";
          timeout = 600;
        };
      };
    };
  };
}
