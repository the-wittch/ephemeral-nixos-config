let
  common =
    { pkgs, ... }:
    {
      environment.persistence."/persist".directories = [ "/var/lib/gdm" ];

      services.xserver.enable = true;

      services.displayManager.gdm.enable = true;
      services.desktopManager.gnome.enable = true;

      services.gnome.gnome-keyring.enable = true;

      environment.systemPackages = with pkgs; [
        nautilus
        gnome-text-editor
        loupe
        file-roller
      ];
    };
in
{
  flake.modules.nixos.gnome =
    { lib, pkgs, ... }:
    {
      imports = [ common ];

      # first db wins
      programs.dconf.profiles.gdm.databases = lib.mkBefore [
        { settings."org/gnome/desktop/interface".color-scheme = "prefer-dark"; }
      ];
      services.desktopManager.gnome.extraGSettingsOverrides = ''
        [org.gnome.shell]
        enabled-extensions=['appindicatorsupport@rgcjonas.gmail.com', 'caffeine@patapon.info']

        # niri and Umbriel lock with Super+Alt+L; GNOME's own Super+L stays
        [org.gnome.settings-daemon.plugins.media-keys]
        screensaver=['<Super>l', '<Super><Alt>l']
      '';
      # an override for a schema that isn't compiled with them is dropped without a word
      services.desktopManager.gnome.extraGSettingsOverridePackages = [ pkgs.gnome-settings-daemon ];

      environment.systemPackages = with pkgs; [
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
      imports = [ common ];
      services.gnome.gnome-initial-setup.enable = false;
      # the full profile gets it from ephemeral-apps
      environment.systemPackages = [ pkgs.gnome-tweaks ];
    };
}
