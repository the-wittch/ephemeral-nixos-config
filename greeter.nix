{
  config,
  lib,
  pkgs,
  settings,
  ...
}:

let
  isPlasma = settings.desktop == "plasma";
  useGdm = config.services.displayManager.gdm.enable;
  kdeDark = import ./lib/kde-dark.nix { inherit lib; };

  dconfDb =
    name: values:
    pkgs.runCommand name { } ''
      mkdir keys
      printf '%s\n' ${lib.escapeShellArg (lib.generators.toDconfINI values)} > keys/settings
      ${lib.getExe' pkgs.dconf "dconf"} compile "$out" keys
    '';

  # programs.dconf.profiles checks every file-db at build time, and greeter-db
  # only exists at runtime, so this profile is written by hand. the databases
  # nixpkgs puts in the gdm profile are read from the option and appended.
  gdmProfileCfg = config.programs.dconf.profiles.gdm;
  toFileDb =
    db:
    if lib.isAttrs db && !lib.isDerivation db then
      if db.keyfiles != [ ] || db.locks != [ ] || db.lockAll then
        throw "greeter.nix: a gdm dconf database uses keyfiles or locks, which gdmProfile does not handle"
      else
        "file-db:${dconfDb "gdm-db" db.settings}"
    else
      "file-db:${db}";
  gdmProfile = pkgs.writeTextDir "etc/dconf/profile/gdm" (
    lib.concatMapStrings (line: line + "\n") (
      lib.optional gdmProfileCfg.enableUserDb "user-db:user"
      ++ [
        "file-db:/var/lib/gdm/greeter-db"
        "file-db:${
          dconfDb "gdm-greeter-defaults" {
            "org/gnome/desktop/interface".color-scheme = "prefer-dark";
          }
        }"
      ]
      ++ map toFileDb gdmProfileCfg.databases
    )
  );

  inherit (import ./packages/scripts.nix { inherit pkgs; }) greeter-sync;
in
{
  # avatars need nothing here: gnome and plasma settings set them through
  # accountsservice, and noctalia syncs its own greeter.
  programs.dconf.packages = lib.mkIf useGdm (lib.mkBefore [ gdmProfile ]);

  systemd.services.greeter-sync = lib.mkIf useGdm {
    description = "Show the user's wallpaper on the GDM login screen";
    after = [ "systemd-tmpfiles-setup.service" ];
    before = [ "display-manager.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      UMask = "0077";
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      PrivateNetwork = true;
      ProtectSystem = "strict";
      ReadWritePaths = [
        "/var/lib/AccountsService"
        "/var/lib/gdm"
      ];
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectHostname = true;
      ProtectClock = true;
      RestrictSUIDSGID = true;
      RestrictAddressFamilies = [ "AF_UNIX" ];
      RestrictNamespaces = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
      SystemCallArchitectures = "native";
      Environment = [ "GREETER_SYNC_USER=${settings.username}" ];
      ExecStart = lib.getExe greeter-sync;
    };
  };

  systemd.paths.greeter-sync = lib.mkIf useGdm {
    description = "Watch the user's dconf database for wallpaper changes";
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathChanged = [ "/home/${settings.username}/.config/dconf/user" ];
  };

  systemd.tmpfiles.rules =
    lib.optionals useGdm [
      "d /var/lib/gdm 0755 root root -"
      "d /var/lib/AccountsService/backgrounds 0755 root root -"
    ]
    # greeter home is /var/lib/plasmalogin, not ~/.config
    ++ lib.optionals isPlasma [
      "d /var/lib/plasmalogin/.config 0755 plasmalogin plasmalogin -"
      "L+ /var/lib/plasmalogin/.config/kdeglobals - - - - ${pkgs.writeText "plasmalogin-kdeglobals" kdeDark.ini}"
    ];
}
