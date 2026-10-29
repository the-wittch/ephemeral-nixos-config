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
        enabled-extensions=['appindicatorsupport@rgcjonas.gmail.com', 'caffeine@patapon.info']
      '';

      services.gnome.gnome-keyring.enable = true;

      environment.systemPackages = with pkgs; [
        gnome-tweaks
        nautilus
        gnome-text-editor
        loupe
        file-roller
        gnome-extension-manager
        gnomeExtensions.appindicator
        gnomeExtensions.caffeine
        # it ships inside gnome-shell, so hide it instead
        (lib.hiPrio (
          runCommand "hide-gnome-extensions-app" { } ''
            mkdir -p $out/share/applications
            sed '/^\[Desktop Entry\]$/a NoDisplay=true' \
              ${gnome-shell}/share/applications/org.gnome.Extensions.desktop \
              > $out/share/applications/org.gnome.Extensions.desktop
          ''
        ))
      ];
    };

  flake.modules.nixos."minimal-gnome" =
    { pkgs, ... }:
    {
      environment.persistence."/persist".directories = [ "/var/lib/gdm" ];

      services.xserver.enable = true;

      services.displayManager.gdm.enable = true;
      services.desktopManager.gnome.enable = true;
      services.gnome.gnome-initial-setup.enable = false;

      services.gnome.gnome-keyring.enable = true;
      security.pam.services.login.enableGnomeKeyring = true;

      environment.systemPackages = with pkgs; [
        gnome-tweaks
        nautilus
        gnome-text-editor
        loupe
        file-roller
      ];
    };
}
