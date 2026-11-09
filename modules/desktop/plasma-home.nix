{ inputs, ... }:
{
  flake.modules.homeManager.plasma =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      fonts = config.stylix.fonts;
      font = f: size: {
        family = f.name;
        pointSize = size;
      };

      schemes = "${config.xdg.dataHome}/color-schemes";
      kde = pkgs.kdePackages;

      # a matugen color role as KDE writes it, r,g,b
      rgb =
        role:
        "{{colors.${role}.default.red}},{{colors.${role}.default.green}},{{colors.${role}.default.blue}}";
      group = name: background: alternate: ''
        [Colors:${name}]
        BackgroundNormal=${rgb background}
        BackgroundAlternate=${rgb alternate}
        ForegroundNormal=${rgb "on_surface"}
        ForegroundInactive=${rgb "on_surface_variant"}
        ForegroundActive=${rgb "primary"}
        ForegroundLink=${rgb "primary"}
        ForegroundVisited=${rgb "tertiary"}
        ForegroundNegative=${rgb "error"}
        ForegroundNeutral=246,116,0
        ForegroundPositive=39,174,96
        DecorationFocus=${rgb "primary"}
        DecorationHover=${rgb "primary"}
      '';
      template = pkgs.writeText "matugen-plasma.colors" ''
        [General]
        ColorScheme=Wallpaper
        Name=Wallpaper

        ${group "View" "surface" "surface_container_low"}
        ${group "Window" "surface_container" "surface_container_high"}
        ${group "Button" "surface_container_high" "surface_container_highest"}
        ${group "Header" "surface_container" "surface_container_low"}
        ${group "Header][Inactive" "surface_container_low" "surface_container"}
        ${group "Tooltip" "surface_container_highest" "surface_container_high"}
        ${group "Complementary" "surface_container_lowest" "surface_container"}
        [Colors:Selection]
        BackgroundNormal=${rgb "primary"}
        BackgroundAlternate=${rgb "primary_container"}
        ForegroundNormal=${rgb "on_primary"}
        ForegroundInactive=${rgb "on_primary"}
        ForegroundActive=${rgb "on_primary"}
        ForegroundLink=${rgb "on_primary"}
        ForegroundVisited=${rgb "on_primary"}
        ForegroundNegative=${rgb "on_primary"}
        ForegroundNeutral=${rgb "on_primary"}
        ForegroundPositive=${rgb "on_primary"}
        DecorationFocus=${rgb "primary"}
        DecorationHover=${rgb "primary"}

        [WM]
        activeBackground=${rgb "surface_container"}
        activeForeground=${rgb "on_surface"}
        activeBlend=${rgb "on_surface"}
        inactiveBackground=${rgb "surface_container_low"}
        inactiveForeground=${rgb "on_surface_variant"}
        inactiveBlend=${rgb "on_surface_variant"}
      '';

      # plasma-apply-colorscheme skips a scheme that's already in use even when its file
      # changed, so a new wallpaper's colors alternate between two names
      apply = pkgs.writeShellScript "apply-wallpaper-colors" ''
        current=$(${kde.kconfig}/bin/kreadconfig6 --file kdeglobals --group General --key ColorScheme)
        if [[ $current == Wallpaper ]]; then
          ${pkgs.gnused}/bin/sed 's/^\(ColorScheme\|Name\)=Wallpaper$/\1=Wallpaper2/' \
            ${schemes}/Wallpaper.colors >${schemes}/Wallpaper2.colors
          exec ${kde.plasma-workspace}/bin/plasma-apply-colorscheme Wallpaper2
        fi
        exec ${kde.plasma-workspace}/bin/plasma-apply-colorscheme Wallpaper
      '';
      matugenConfig = pkgs.writeText "matugen.toml" ''
        [config]

        [templates.plasma]
        input_path = "${template}"
        output_path = "${schemes}/Wallpaper.colors"
        post_hook = "${apply}"
      '';

      follow = pkgs.writeShellApplication {
        name = "plasma-wallpaper-colors";
        runtimeInputs = with pkgs; [
          coreutils
          findutils
          gnused
          matugen
        ];
        text = ''
          rc=''${XDG_CONFIG_HOME:-$HOME/.config}/plasma-org.kde.plasma.desktop-appletsrc
          state=''${XDG_STATE_HOME:-$HOME/.local/state}/ephemeral/plasma-wallpaper

          image=""
          [[ -f $rc ]] && image=$(sed -n 's|^Image=\(file://\)\{0,1\}||p' "$rc" | head -n 1)
          # Plasma leaves Image unset until a wallpaper is picked
          [[ -n $image ]] || image=/run/current-system/sw/share/wallpapers/Next
          # a wallpaper package: take its largest picture
          if [[ -d $image ]]; then
            image=$(find "$image" -path '*/contents/images/*' -type f | sort -V | tail -n 1)
          fi
          [[ -f $image ]] || exit 0

          if [[ $image == "$(cat "$state" 2>/dev/null)" && -f ${schemes}/Wallpaper.colors ]]; then
            exit 0
          fi
          mkdir -p ${schemes} "$(dirname "$state")"
          matugen image --config ${matugenConfig} --mode dark --source-color-index 0 --quiet "$image"
          printf '%s\n' "$image" >"$state"
        '';
      };
    in
    {
      imports = [ inputs.plasma-manager.homeModules.plasma-manager ];

      # its look-and-feel is reapplied on every rebuild and would put Catppuccin back over the wallpaper colors
      stylix.targets.kde.enable = false;

      home.packages = [
        kde.krohnkite
        follow
      ];

      programs.plasma = {
        enable = true;

        # what stylix's KDE target set, besides the colors
        workspace.cursor = {
          theme = config.stylix.cursor.name;
          size = config.stylix.cursor.size;
        };
        fonts = {
          general = font fonts.sansSerif fonts.sizes.applications;
          fixedWidth = font fonts.monospace fonts.sizes.terminal;
          small = font fonts.sansSerif (fonts.sizes.desktop - 2);
          toolbar = font fonts.sansSerif fonts.sizes.desktop;
          menu = font fonts.sansSerif fonts.sizes.desktop;
          windowTitle = font fonts.sansSerif fonts.sizes.desktop;
        };

        configFile = {
          # KDE would copy its settings over the GTK files Home Manager manages
          kded5rc."Module-gtkconfig".autoload = false;
          kdeglobals.General.accentColorFromWallpaper = false;

          kwinrc.Plugins.krohnkiteEnabled = true;
          kwinrc."Script-krohnkite" = {
            screenDefaultLayout = ":threecolumn";
            monocleLayoutOrder = 1;
            threeColumnLayoutOrder = 2;
            tileLayoutOrder = 3;
            floatingClass = "steam";
            tileLayoutGap = 10;
            screenGapLeft = 12;
            screenGapRight = 12;
            screenGapTop = 12;
            screenGapBottom = 12;
            screenGapBetween = 10;
            soleWindowWidth = 75;
            soleWindowHeight = 95;
          };
        };
      };

      systemd.user.services.plasma-wallpaper-colors = {
        Unit = {
          Description = "Plasma colors from the wallpaper";
          After = [ "plasma-workspace.target" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe follow;
        };
        Install.WantedBy = [ "plasma-workspace.target" ];
      };
      systemd.user.paths.plasma-wallpaper-colors = {
        Unit.Description = "Watch the Plasma wallpaper";
        Path.PathChanged = "%h/.config/plasma-org.kde.plasma.desktop-appletsrc";
        Install.WantedBy = [ "plasma-workspace.target" ];
      };
    };
}
