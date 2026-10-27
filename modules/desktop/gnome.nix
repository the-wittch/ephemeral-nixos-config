{
  flake.modules.nixos.gnome =
    { lib, pkgs, ... }:
    {
      environment.persistence."/persist".directories = [ "/var/lib/gdm" ];

      services.xserver.enable = true;

      services.displayManager.gdm.enable = true;
      services.desktopManager.gnome.enable = true;
      # first db wins
      programs.dconf.profiles.gdm.databases = lib.mkBefore [
        { settings."org/gnome/desktop/interface".color-scheme = "prefer-dark"; }
      ];
      services.desktopManager.gnome.extraGSettingsOverrides = ''
        [org.gnome.shell]
        enabled-extensions=['appindicatorsupport@rgcjonas.gmail.com']
      '';

      services.gnome.gnome-keyring.enable = true;

      environment.systemPackages = with pkgs; [
        gnome-tweaks
        nautilus
        gnome-text-editor
        loupe
        file-roller
        gnomeExtensions.appindicator
      ];
    };
}
