{ inputs, ... }:
{
  ephemeral.apps = {
    steam = {
      label = "Steam";
      category = "Gaming";
      description = "the Steam store with Proton for Windows games";
      unfree = [
        "steam"
        "steam-unwrapped"
      ];
      nixos.programs.steam = {
        enable = true;
        remotePlay.openFirewall = false;
        dedicatedServer.openFirewall = false;
      };
    };
    lutris = {
      label = "Lutris";
      category = "Gaming";
      description = "game launcher for many stores and emulators";
      flatpak = "net.lutris.Lutris";
      defaultOn = [ "handheld" ];
      # Lutris's own install scripts for these, which install the launcher the first time and
      # start it after, once Lutris has asked whether to play or install again
      steamShortcuts = [
        { name = "Lutris"; }
        {
          name = "Battle.net";
          args = "lutris:battlenet";
        }
        {
          name = "EA app";
          args = "lutris:ea-app";
        }
        {
          name = "Ubisoft Connect";
          args = "lutris:ubisoft-connect";
        }
        {
          name = "Rockstar Games Launcher";
          args = "lutris:rockstar-games-launcher";
        }
      ];
    };
    heroic = {
      label = "Heroic";
      category = "Gaming";
      description = "Epic and GOG and Amazon games";
      flatpak = "com.heroicgameslauncher.hgl";
      defaultOn = [ "handheld" ];
      steamShortcuts = [ { name = "Heroic"; } ];
    };
    prismlauncher = {
      label = "Prism Launcher";
      category = "Gaming";
      description = "Minecraft launcher";
      flatpak = "org.prismlauncher.PrismLauncher";
      steamShortcuts = [ { name = "Minecraft (Prism Launcher)"; } ];
    };
    decky-loader = {
      label = "Decky Loader";
      category = "Gaming";
      description = "plugins for Game Mode from the Decky store";
      defaultOn = [ "handheld" ];
      desktops = [ "handheld" ];
      warn = "Decky runs as root and its plugins can ask to as well; it turns on Steam's remote debugging port for every program on this machine";
      nixos =
        {
          config,
          lib,
          pkgs,
          ...
        }:
        let
          decky = pkgs.callPackage ./_decky-loader.nix { };
          user = config.ephemeral.settings.username;
          state = "/var/lib/decky-loader";
        in
        {
          # As upstream runs it: as root, as it installs plugins and runs the ones that ask for
          # root, and the rest as the user
          systemd.services.decky-loader = {
            description = "Decky Loader, plugins for Game Mode";
            wantedBy = [ "multi-user.target" ];
            after = [ "network.target" ];
            environment = {
              UNPRIVILEGED_USER = user;
              UNPRIVILEGED_PATH = state;
              PLUGIN_PATH = "${state}/plugins";
            };
            serviceConfig = {
              ExecStart = lib.getExe decky;
              # its plugins stop on their own once it's gone
              KillMode = "process";
              TimeoutStopSec = 45;
            };
          };
          # the plugins, their settings and its own
          preservation.preserveAt."/persist".directories = [
            {
              directory = state;
              inherit user;
              inherit (config.users.users.${user}) group;
            }
          ];
        };
      # how Decky reaches Steam's menus
      homeManager.home.file.".local/share/Steam/.cef-enable-remote-debugging".text = "";
    };
    gamemode = {
      label = "GameMode";
      category = "Gaming";
      description = "raise performance while a game runs";
      nixos.programs.gamemode.enable = true;
    };
    mangohud = {
      label = "MangoHud";
      category = "Gaming";
      description = "FPS and temperature overlay";
      package = "mangohud";
    };
    protonup-qt = {
      label = "ProtonUp-Qt";
      category = "Gaming";
      description = "install Proton-GE and Wine-GE";
      package = "protonup-qt";
    };
    zork = {
      label = "Zork I-III";
      category = "Gaming";
      description = "the Infocom text adventures in a CRT terminal";
      nixos = {
        imports = [ inputs.zork-nix.nixosModules.default ];
        programs.zork-nix.enable = true;
      };
    };
  };
}
