let
  uri = "file:///run/current-system/sw/share/backgrounds/ephemeral/wallpaper.png";
  # the flat colour round the boot menu's snowflake, the navy in the middle of the wallpaper
  bootBackdrop = "0d0b26";

  gnome = {
    services.desktopManager.gnome.extraGSettingsOverrides = ''
      [org.gnome.desktop.background]
      picture-uri='${uri}'
      picture-uri-dark='${uri}'
      picture-options='zoom'

      [org.gnome.desktop.screensaver]
      picture-uri='${uri}'
    '';

    programs.dconf.profiles.gdm.databases = [
      {
        settings."org/gnome/desktop/background" = {
          picture-uri = uri;
          picture-uri-dark = uri;
          picture-options = "zoom";
        };
      }
    ];
  };

  plasma = {
    services.displayManager.plasma-login-manager.settings = {
      Greeter.WallpaperPluginId = "org.kde.image";
      "Greeter][Wallpaper][org.kde.image][General".Image = uri;
    };
  };
in
{
  flake.modules.nixos.pc =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.ephemeral.wallpaper = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = "The rendered wallpaper; the png is share/backgrounds/ephemeral/wallpaper.png.";
        # nixos logo by simon frankau, tim cuthbertson and daniel baker. cc-by-4.0, github.com/NixOS/branding
        default =
          pkgs.runCommand "ephemeral-wallpaper"
            {
              nativeBuildInputs = [ pkgs.librsvg ];
              FONTCONFIG_FILE = pkgs.makeFontsConf { fontDirectories = [ pkgs.jetbrains-mono ]; };
            }
            ''
              mkdir -p $out/share/backgrounds/ephemeral
              rsvg-convert -w 3840 -h 2160 ${../assets/wallpaper.svg} \
                -o $out/share/backgrounds/ephemeral/wallpaper.png
              awk -v bg=${bootBackdrop} -f ${./_boot-menu.awk} ${../assets/wallpaper.svg} >boot.svg
              # the filter goes by the svg's lines; a changed svg fails here rather than drawing wrong
              grep -q 'viewBox="1020 0 1800 1800"' boot.svg
              grep -q 'translate(1920 900)' boot.svg
              if grep -q -e '<text ' -e '^<path d="M ' boot.svg; then exit 1; fi
              rsvg-convert -w 900 -h 900 boot.svg -o $out/share/backgrounds/ephemeral/boot-menu.png
            '';
      };

      config = {
        boot.loader.limine.style = {
          wallpapers = lib.mkForce [
            "${config.ephemeral.wallpaper}/share/backgrounds/ephemeral/boot-menu.png"
          ];
          wallpaperStyle = lib.mkForce "centered";
          backdrop = lib.mkForce bootBackdrop;
        };
        environment.systemPackages = [ config.ephemeral.wallpaper ];
        environment.pathsToLink = [ "/share/backgrounds" ];
      };
    };

  flake.modules.nixos.gnome = gnome;
  flake.modules.nixos."minimal-gnome" = gnome;
  flake.modules.nixos.plasma = plasma;
  flake.modules.nixos."minimal-plasma" = plasma;
}
