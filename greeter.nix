{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

let
  desktop = settings.desktop;
  isPlasma = desktop == "plasma";
  isGnome = desktop == "gnome";
  isNiri = desktop == "niri";
  home = "/home/${settings.username}";
  kdeDark = import ./lib/kde-dark.nix { inherit lib; };

  dconfDb =
    name: values:
    pkgs.runCommand name { } ''
      mkdir keys
      printf '%s\n' ${lib.escapeShellArg (lib.generators.toDconfINI values)} > keys/settings
      ${lib.getExe' pkgs.dconf "dconf"} compile "$out" keys
    '';

  # hand-built because programs.dconf.profiles checks every file-db at build
  # time, and greeter-db only exists at runtime. the tail mirrors the
  # programs.dconf.profiles.gdm list in nixpkgs gdm.nix; recheck it on bumps.
  gdmCfg = config.services.displayManager.gdm;
  gdmProfile = pkgs.writeTextDir "etc/dconf/profile/gdm" (
    lib.concatMapStrings (line: line + "\n") (
      [
        "user-db:user"
        "file-db:/var/lib/gdm/greeter-db"
        "file-db:${
          dconfDb "gdm-greeter-defaults" {
            "org/gnome/desktop/interface".color-scheme = "prefer-dark";
          }
        }"
      ]
      ++
        lib.optional (!gdmCfg.autoSuspend)
          "file-db:${
            dconfDb "gdm-power" {
              "org/gnome/settings-daemon/plugins/power" = {
                sleep-inactive-ac-type = "nothing";
                sleep-inactive-battery-type = "nothing";
                sleep-inactive-ac-timeout = lib.gvariant.mkInt32 0;
                sleep-inactive-battery-timeout = lib.gvariant.mkInt32 0;
              };
            }
          }"
      ++
        lib.optional (gdmCfg.banner != null)
          "file-db:${
            dconfDb "gdm-banner" {
              "org/gnome/login-screen" = {
                banner-message-enable = true;
                banner-message-text = gdmCfg.banner;
              };
            }
          }"
      ++ [ "file-db:${pkgs.gdm}/share/gdm/greeter-dconf-defaults" ]
    )
  );

  greeter-sync = pkgs.writeShellApplication {
    name = "greeter-sync";
    runtimeInputs = with pkgs; [
      coreutils
      dconf
      diffutils
      systemd
      util-linux
    ];
    text = builtins.readFile ./scripts/greeter-sync.sh;
  };
in
{
  programs.dconf.packages = lib.mkBefore (lib.optionals isGnome [ gdmProfile ]);

  systemd.services.greeter-sync = {
    description = "Publish avatar and wallpaper for the greeter";
    after = [
      "accounts-daemon.service"
      "systemd-tmpfiles-setup.service"
    ];
    before = [ "display-manager.service" ];
    wants = [ "accounts-daemon.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "full";
      # plasma publishes /etc/plasmalogin.conf
      ReadWritePaths = lib.optionals isPlasma [ "/etc" ];
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      ProtectHostname = true;
      ProtectClock = true;
      RestrictSUIDSGID = true;
      RestrictAddressFamilies = [ "AF_UNIX" ];
      LockPersonality = true;
      SystemCallArchitectures = "native";
      Environment = [
        "GREETER_SYNC_USER=${settings.username}"
        "GREETER_SYNC_DESKTOP=${desktop}"
      ];
      ExecStart = lib.getExe greeter-sync;
    };
  };

  systemd.paths.greeter-sync = {
    description = "Watch avatar and wallpaper files";
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathChanged = [
      "${home}/.face"
      "${home}/.face.icon"
    ]
    ++ lib.optionals isGnome [ "${home}/.config/dconf/user" ]
    ++ lib.optionals isPlasma [
      "${home}/.config/plasma-org.kde.plasma.desktop-appletsrc"
      "${home}/.config/kscreenlockerrc"
    ]
    ++ lib.optionals isNiri [
      "${home}/.local/state/noctalia/settings.toml"
      "${home}/.config/noctalia/config.toml"
    ];
  };

  # greeter home is /var/lib/plasmalogin, not ~/.config
  systemd.tmpfiles.rules = lib.mkIf isPlasma [
    "d /var/lib/plasmalogin/.config 0755 plasmalogin plasmalogin -"
    "L+ /var/lib/plasmalogin/.config/kdeglobals - - - - ${pkgs.writeText "plasmalogin-kdeglobals" kdeDark.ini}"
  ];
}
