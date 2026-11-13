{
  flake.modules.nixos.pc =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      options.ephemeral.flathubRepo = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = "The pinned flathub.flatpakrepo file.";
        # pinned: it holds flathub's signing key
        default = pkgs.fetchurl {
          url = "https://dl.flathub.org/repo/flathub.flatpakrepo";
          hash = "sha256-M3HdJQ5h2eFjNjAHP+/aFTzUQm9y9K+gwzc64uj+oDo=";
        };
      };

      config.services.flatpak.enable = true;
      config.environment.persistence."/persist".directories = [ "/var/lib/flatpak" ];

      config.systemd.services.flatpak-flathub = {
        description = "Add Flathub Flatpak remote";
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.flatpak ];
        serviceConfig = config.ephemeral.sandbox // {
          Type = "oneshot";
          RemainAfterExit = true;
          StateDirectory = "flatpak";
        };
        script = ''
          flatpak remote-add --system --if-not-exists flathub ${config.ephemeral.flathubRepo}
        '';
      };
    };
}
