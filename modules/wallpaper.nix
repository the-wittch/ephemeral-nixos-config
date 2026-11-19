let
  uri = "file:///run/current-system/sw/share/backgrounds/ephemeral/wallpaper.png";

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
    let
      res = config.ephemeral.settings.bootResolution;
      size = map lib.toInt (lib.splitString "x" (if res == "" then "3840x2160" else res));
      w = lib.elemAt size 0;
      h = lib.elemAt size 1;
      # The part of the 3840x2160 drawing with the screen's shape, around its middle: a narrower
      # screen loses some of the sides, a wider one some of the top and bottom. Drawn at the
      # screen's own size, Limine shows it pixel for pixel; it scales without smoothing, and
      # stretches each way on its own.
      narrower = w * 2160 <= h * 3840;
      cropW = if narrower then 2160 * w / h else 3840;
      cropH = if narrower then 2160 else 3840 * h / w;
      viewBox = lib.concatMapStringsSep " " toString [
        ((3840 - cropW) / 2)
        ((2160 - cropH) / 2)
        cropW
        cropH
      ];
      # nixos logo by simon frankau, tim cuthbertson and daniel baker. cc-by-4.0, github.com/NixOS/branding
      render =
        name: script:
        pkgs.runCommand name {
          nativeBuildInputs = [ pkgs.librsvg ];
          FONTCONFIG_FILE = pkgs.makeFontsConf { fontDirectories = [ pkgs.jetbrains-mono ]; };
        } script;
    in
    {
      options.ephemeral.wallpaper = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = "The rendered wallpaper; the png is share/backgrounds/ephemeral/wallpaper.png.";
        default = render "ephemeral-wallpaper" ''
          mkdir -p $out/share/backgrounds/ephemeral
          rsvg-convert -w 3840 -h 2160 ${../assets/wallpaper.svg} \
            -o $out/share/backgrounds/ephemeral/wallpaper.png
        '';
      };

      config = {
        boot.loader.limine.style = {
          # without the words; each <text> element is on a line of its own
          wallpapers = lib.mkForce [
            (render "ephemeral-boot-wallpaper.png" ''
              grep -v '<text ' ${../assets/wallpaper.svg} |
                sed 's/width="3840" height="2160" viewBox="0 0 3840 2160"/width="${toString cropW}" height="${toString cropH}" viewBox="${viewBox}"/' >boot.svg
              # fails the build if the svg's root changed and the crop no longer applies
              grep -q 'height="${toString cropH}" viewBox="${viewBox}"' boot.svg
              rsvg-convert -w ${toString w} -h ${toString h} boot.svg -o $out
            '')
          ];
          interface.resolution = lib.mkIf (res != "") res;
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
