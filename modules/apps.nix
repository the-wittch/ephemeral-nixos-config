{ withSystem, ... }:
{
  flake.modules.nixos.full =
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
      options.ephemeral.passCli = lib.mkOption {
        type = lib.types.package;
        readOnly = true;
        description = "The pass-cli build in use, picked by useFlakePassCli.";
      };

      config = {
        ephemeral.passCli =
          if config.ephemeral.settings.useFlakePassCli then packages.pass-cli else pkgs.proton-pass-cli;

        programs.nix-ld.enable = true;

        environment.systemPackages =
          lib.attrValues (
            removeAttrs packages [
              "pass-cli"
              "check-no-secrets"
            ]
          )
          ++ [ config.ephemeral.passCli ]
          ++ (with pkgs; [
            firefox
            ghostty
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
            file
            usbutils
            pciutils
            wireguard-tools
            opensnitch-ui
            gum
          ]);

        environment.sessionVariables = {
          TERMINAL = "ghostty";
          PROTON_PASS_LINUX_KEYRING = "dbus";
          PASS_SSH_VAULT = config.ephemeral.settings.passSshVault;
        };
      };
    };

  flake.modules.nixos.extras =
    { pkgs, ... }:
    {
      ephemeral.unfreePackages = [
        "steam"
        "steam-unwrapped"
        "vscode"
        "unrar"
      ];

      programs.steam = {
        enable = true;
        remotePlay.openFirewall = false;
        dedicatedServer.openFirewall = false;
      };

      environment.systemPackages = with pkgs; [
        vscode
        brave-origin
        vlc
        distrobox
        syncthingtray-minimal
        p7zip
        unrar
        git-crypt
        age
      ];
    };
}
