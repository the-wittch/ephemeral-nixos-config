{
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
  kdeDark = import ./lib/kde-dark.nix { inherit lib; };
  greeterInterface = pkgs.writeText "gdm-interface" ''
    [org/gnome/desktop/interface]
    color-scheme='prefer-dark'
  '';
  greeterDefaults = pkgs.runCommand "gdm-greeter-defaults" { } ''
    mkdir -p keys "$out"
    cp ${greeterInterface} keys/interface
    ${lib.getExe' pkgs.dconf "dconf"} compile "$out/db" keys
  '';
  gdmProfile = pkgs.writeText "gdm-dconf-profile" ''
    user-db:user
    file-db:/var/lib/gdm/greeter-db
    file-db:${greeterDefaults}/db
  '';
  greeter-sync = pkgs.writeShellApplication {
    name = "greeter-sync";
    runtimeInputs = with pkgs; [
      coreutils
      dconf
      systemd
      util-linux
    ];
    text = builtins.readFile ./scripts/greeter-sync.sh;
  };
in
{
  assertions = [
    {
      assertion = lib.elem desktop [
        "plasma"
        "gnome"
        "niri"
      ];
      message = "settings.desktop must be one of: plasma, gnome, niri (got: ${desktop})";
    }
    {
      assertion = builtins.match "[A-Za-z_][A-Za-z0-9._-]{0,31}" settings.username != null;
      message = "settings.username must be a plain account name";
    }
  ];

  environment.persistence."/persist".directories =
    lib.optionals isPlasma [ "/var/lib/plasmalogin" ]
    ++ lib.optionals isGnome [ "/var/lib/gdm" ]
    ++ lib.optionals isNiri [ "/var/lib/noctalia-greeter" ];

  # xwayland and some greeters still want this
  services.xserver.enable = lib.mkIf (isPlasma || isGnome) true;

  # plasma. unstable uses plasma-login-manager, not sddm
  services.desktopManager.plasma6.enable = lib.mkIf isPlasma true;
  services.displayManager.plasma-login-manager.enable = lib.mkIf isPlasma true;

  boot.plymouth = lib.mkIf isPlasma {
    theme = "breeze";
    themePackages = [ pkgs.kdePackages.breeze-plymouth ];
  };

  # gnome. gdm is wayland-only on gnome 50, don't set gdm.wayland
  services.displayManager.gdm.enable = lib.mkIf isGnome true;
  services.desktopManager.gnome.enable = lib.mkIf isGnome true;
  # user-db is tmpfs. greeter-db is the persisted override.
  programs.dconf.profiles = lib.mkIf isGnome {
    gdm = gdmProfile;
  };

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
      "/home/${settings.username}/.face"
      "/home/${settings.username}/.face.icon"
    ]
    ++ lib.optionals isGnome [ "/home/${settings.username}/.config/dconf/user" ]
    ++ lib.optionals isPlasma [
      "/home/${settings.username}/.config/plasma-org.kde.plasma.desktop-appletsrc"
      "/home/${settings.username}/.config/kscreenlockerrc"
    ]
    ++ lib.optionals isNiri [
      "/home/${settings.username}/.local/state/noctalia/settings.toml"
      "/home/${settings.username}/.config/noctalia/config.toml"
    ];
  };

  # greeter home is /var/lib/plasmalogin, not ~/.config
  systemd.tmpfiles.rules = lib.mkIf isPlasma [
    "d /var/lib/plasmalogin/.config 0755 plasmalogin plasmalogin -"
    "L+ /var/lib/plasmalogin/.config/kdeglobals - - - - ${pkgs.writeText "plasmalogin-kdeglobals" kdeDark.ini}"
  ];

  # plasma sets this itself
  environment.sessionVariables = lib.mkIf (!isPlasma) {
    QT_QPA_PLATFORMTHEME = "gtk3";
  };
  # secret service for pass-cli (PROTON_PASS_LINUX_KEYRING=dbus).
  # plasma6 already unlocks kwallet, which provides the same bus name.
  # gnome-keyring on plasma would fight it.
  services.gnome.gnome-keyring.enable = isGnome || isNiri;
  # niri + noctalia
  programs.niri.enable = lib.mkIf isNiri true;
  programs.noctalia = lib.mkIf isNiri {
    enable = true;
    systemd.enable = true;
    recommendedServices.enable = true;
  };
  # greetd. niri shows up once programs.niri.enable is on
  services.displayManager.noctalia-greeter.enable = lib.mkIf isNiri true;
  services.displayManager.noctalia-greeter.passwordlessSyncUsers = lib.mkIf isNiri [
    settings.username
  ];
  services.displayManager.noctalia-greeter.settings = lib.mkIf isNiri {
    appearance.theme_mode = "dark";
  };

  environment.systemPackages =
    with pkgs;
    lib.optionals isPlasma [
      kdePackages.kate
      kdePackages.ark
      kdePackages.okular
      kdePackages.gwenview
      kdePackages.spectacle
      kdePackages.discover
      kdePackages.partitionmanager
    ]
    ++ lib.optionals isGnome [
      gnome-tweaks
      nautilus
      gnome-text-editor
      loupe
      file-roller
    ]
    ++ lib.optionals isNiri [
      xwayland-satellite
      fuzzel
      brightnessctl
      playerctl
    ];
}
