{ inputs, ... }:
{
  flake.modules.nixos.pc =
    { config, pkgs, ... }:
    {
      imports = [ inputs.stylix.nixosModules.stylix ];

      stylix = {
        enable = true;
        polarity = "dark";
        base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
        image = "${config.ephemeral.wallpaper}/share/backgrounds/ephemeral/wallpaper.png";

        # would rebuild gnome-shell and others from source
        overlays.enable = false;

        fonts = {
          sansSerif = {
            package = pkgs.noto-fonts;
            name = "Noto Sans";
          };
          serif = {
            package = pkgs.noto-fonts;
            name = "Noto Serif";
          };
          monospace = {
            package = pkgs.jetbrains-mono;
            name = "JetBrains Mono";
          };
          emoji = {
            package = pkgs.noto-fonts-color-emoji;
            name = "Noto Color Emoji";
          };
        };

        cursor = {
          package = pkgs.catppuccin-cursors.mochaDark;
          name = "catppuccin-mocha-dark-cursors";
          size = 24;
        };

        # a browser policy: "managed by your organization"
        targets.chromium.enable = false;
      };

      home-manager.sharedModules = [
        {
          stylix.targets = {
            # the wallpaper is only a default
            gnome.image.enable = false;
            kde.useWallpaper = false;
            # makes settings.json read-only
            vscode.enable = false;
            # unused, and warns about a renamed option
            rofi.enable = false;
          };
        }
      ];
    };

  flake.modules.nixos.gnome =
    { pkgs, ... }:
    {
      # qt is themed system-wide here
      home-manager.sharedModules = [ { stylix.targets.qt.enable = false; } ];
      # stylix removes them
      environment.systemPackages = [ pkgs.gnome-backgrounds ];
    };

  flake.modules.nixos.plasma.home-manager.sharedModules = [ { stylix.targets.qt.enable = false; } ];
}
