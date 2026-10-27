{ withSystem, ... }:
{
  flake.modules.nixos.pc =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      packages = withSystem pkgs.stdenv.hostPlatform.system ({ config, ... }: config.packages);
    in
    {
      options.ephemeral.desktopApps = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the desktop apps listed in apps.nix.";
      };

      config = {
        ephemeral.unfreePackages = [
          "steam"
          "steam-unwrapped"
          "vscode"
          "unrar"
        ];

        programs.steam = {
          enable = config.ephemeral.desktopApps;
          remotePlay.openFirewall = false;
          dedicatedServer.openFirewall = false;
        };

        programs.nix-ld.enable = true;

        environment.systemPackages =
          (with packages; [
            ephemeral-update
            flatpak-apps
            smb-setup
            controld-setup
            update-pass-cli
            settings-from-pass
            ssh-pubs-from-pass
            luks-header-backup
            (if config.ephemeral.settings.useFlakePassCli then pass-cli else pkgs.proton-pass-cli)
          ])
          ++ lib.optionals config.ephemeral.desktopApps (
            with pkgs;
            [
              vscode
              firefox
              brave-origin
              ghostty
              vlc
              git
              curl
              wget
              ripgrep
              wl-clipboard
              htop
              dig
              mkpasswd
              unzip
              zip
              p7zip
              file
              usbutils
              pciutils
              wireguard-tools
              distrobox
              syncthingtray-minimal
              opensnitch-ui
              gum

              git-crypt
              age
              unrar
            ]
          );

        environment.sessionVariables = {
          TERMINAL = "ghostty";
          PROTON_PASS_LINUX_KEYRING = "dbus";
        };
      };
    };
}
