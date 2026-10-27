{ inputs, ... }:
{
  flake.modules.nixos.pc =
    { config, pkgs, ... }:
    {
      imports = [ inputs.stylix.nixosModules.stylix ];

      stylix = {
        enable = true;
        polarity = "dark";
        # inline, so evaluating doesn't need base16-schemes built
        base16Scheme = {
          system = "base16";
          name = "Catppuccin Mocha";
          author = "https://github.com/catppuccin/catppuccin";
          variant = "dark";
          palette = {
            base00 = "#1e1e2e";
            base01 = "#313244";
            base02 = "#45475a";
            base03 = "#6c7086";
            base04 = "#a6adc8";
            base05 = "#cdd6f4";
            base06 = "#f5e0dc";
            base07 = "#b4befe";
            base08 = "#f38ba8";
            base09 = "#fab387";
            base0A = "#f9e2af";
            base0B = "#a6e3a1";
            base0C = "#94e2d5";
            base0D = "#89b4fa";
            base0E = "#cba6f7";
            base0F = "#f2cdcd";
          };
        };
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
    { lib, pkgs, ... }:
    {
      # the gnome platform theme (qgnomeplatform) breaks qt tray icons on wayland
      stylix.targets.qt.platform = lib.mkForce "qtct";
      # stylix removes them
      environment.systemPackages = [ pkgs.gnome-backgrounds ];
    };

  flake.modules.nixos.plasma.home-manager.sharedModules = [ { stylix.targets.qt.enable = false; } ];
}
