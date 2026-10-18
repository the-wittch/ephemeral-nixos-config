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
  ];

  environment.persistence."/persist".directories =
    lib.optionals isPlasma [ "/var/lib/plasmalogin" ]
    ++ lib.optionals isGnome [ "/var/lib/gdm" ];

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
