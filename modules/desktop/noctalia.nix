{ config, ... }:
let
  hm = config.ephemeral.aspects.homeManager;
  nixos = config.ephemeral.aspects.nixos;
in
{
  flake.modules.nixos.noctalia-base =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      greeter = config.services.greetd.settings.default_session.user;
    in
    {
      imports = [ nixos.graphical ];

      programs.noctalia = {
        enable = true;
        systemd.enable = true;
        recommendedServices.enable = true;
      };
      services.displayManager.noctalia-greeter.enable = true;
      # the greeter writes its state there, as the module's own tmpfiles rule sets it up
      preservation.preserveAt."/persist".directories = [
        {
          directory = "/var/lib/noctalia-greeter";
          user = greeter;
          group = config.users.users.${greeter}.group;
          mode = "0750";
        }
      ];

      services.gnome.gnome-keyring.enable = true;
      # the greeter logs in through greetd
      security.pam.services.greetd.enableGnomeKeyring = true;

      # the screen reader, which GNOME and Plasma turn on themselves; niri starts it with Super+Alt+S
      services.orca.enable = true;

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
